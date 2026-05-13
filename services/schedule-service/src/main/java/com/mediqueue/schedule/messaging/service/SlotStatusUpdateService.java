package com.mediqueue.schedule.messaging.service;

import com.mediqueue.schedule.domain.DentistSlot;
import com.mediqueue.schedule.domain.enums.SlotDisplayStatus;
import com.mediqueue.schedule.repository.DentistSlotRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

/**
 * Transactional service that applies idempotent slot state transitions
 * driven by appointment lifecycle events consumed from RabbitMQ.
 *
 * <p>Idempotency guarantee: if the slot is already in the target state
 * (or in a "later" terminal state like BOOKED), the update is silently
 * skipped to prevent backward transitions.</p>
 *
 * @since 0.0.2
 */
@Service
@RequiredArgsConstructor
public class SlotStatusUpdateService {

    private static final Logger log = LoggerFactory.getLogger(SlotStatusUpdateService.class);

    private final DentistSlotRepository dentistSlotRepository;

    /**
     * Marks the slot as {@link SlotDisplayStatus#HELD}.
     * Skipped if the slot is already HELD, BOOKED, or BLOCKED.
     *
     * @param slotId       the target slot
     * @param appointmentId used for structured logging only
     */
    @Transactional
    public void markHeld(UUID slotId, UUID appointmentId) {
        applyTransition(slotId, appointmentId, SlotDisplayStatus.HELD,
                new SlotDisplayStatus[]{SlotDisplayStatus.BOOKED, SlotDisplayStatus.BLOCKED, SlotDisplayStatus.HELD});
    }

    /**
     * Marks the slot as {@link SlotDisplayStatus#BOOKED}.
     * Skipped if already BOOKED or BLOCKED.
     *
     * @param slotId       the target slot
     * @param appointmentId used for structured logging only
     */
    @Transactional
    public void markBooked(UUID slotId, UUID appointmentId) {
        applyTransition(slotId, appointmentId, SlotDisplayStatus.BOOKED,
                new SlotDisplayStatus[]{SlotDisplayStatus.BOOKED, SlotDisplayStatus.BLOCKED});
    }

    /**
     * Marks the slot as {@link SlotDisplayStatus#AVAILABLE}.
     * Skipped if the slot is BLOCKED (manual administrative block must not be overridden by events).
     *
     * @param slotId       the target slot
     * @param appointmentId used for structured logging only
     */
    @Transactional
    public void markAvailable(UUID slotId, UUID appointmentId) {
        applyTransition(slotId, appointmentId, SlotDisplayStatus.AVAILABLE,
                new SlotDisplayStatus[]{SlotDisplayStatus.AVAILABLE, SlotDisplayStatus.BLOCKED});
    }

    private void applyTransition(UUID slotId, UUID appointmentId,
                                  SlotDisplayStatus target, SlotDisplayStatus[] skipIfIn) {
        Optional<DentistSlot> slotOpt = dentistSlotRepository.findById(slotId);

        if (slotOpt.isEmpty()) {
            log.warn("slot_not_found_discarding slotId={} appointmentId={} targetStatus={}",
                    slotId, appointmentId, target);
            return;
        }

        DentistSlot slot = slotOpt.get();

        for (SlotDisplayStatus skip : skipIfIn) {
            if (slot.getStatus() == skip) {
                log.debug("slot_transition_skipped slotId={} currentStatus={} targetStatus={}",
                        slotId, slot.getStatus(), target);
                return;
            }
        }

        slot.setStatus(target);
        slot.setUpdatedAt(LocalDateTime.now());
        dentistSlotRepository.save(slot);

        log.info("slot_status_updated slotId={} appointmentId={} newStatus={}",
                slotId, appointmentId, target);
    }
}
