package com.mediqueue.appointment.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.appointment.domain.Appointment;
import com.mediqueue.appointment.domain.AppointmentAudit;
import com.mediqueue.appointment.domain.AppointmentHold;
import com.mediqueue.appointment.domain.OutboxEvent;
import com.mediqueue.appointment.domain.enums.AppointmentStatus;
import com.mediqueue.appointment.domain.enums.HoldStatus;
import com.mediqueue.appointment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.appointment.events.published.AppointmentExpiredEvent;
import com.mediqueue.appointment.repository.AppointmentAuditRepository;
import com.mediqueue.appointment.repository.AppointmentHoldRepository;
import com.mediqueue.appointment.repository.AppointmentRepository;
import com.mediqueue.appointment.repository.IdempotencyKeyRepository;
import com.mediqueue.appointment.repository.OutboxEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

/**
 * Scheduled job that detects expired appointment holds and transitions
 * the associated appointments to {@code EXPIRED} status.
 *
 * <p>Each hold is processed in its own transaction so that a failure
 * on one hold does not prevent the remaining holds from being expired.</p>
 *
 * @since 0.0.1
 */
@Component
public class HoldExpirationScheduler {

    private static final Logger log = LoggerFactory.getLogger(HoldExpirationScheduler.class);

    private final AppointmentHoldRepository holdRepository;
    private final AppointmentRepository appointmentRepository;
    private final AppointmentAuditRepository auditRepository;
    private final OutboxEventRepository outboxEventRepository;
    private final IdempotencyKeyRepository idempotencyKeyRepository;
    private final ObjectMapper objectMapper;
    private final TransactionTemplate transactionTemplate;
    private final int maxHoldsPerScan;
    private final boolean holdExpirationEnabled;

    public HoldExpirationScheduler(AppointmentHoldRepository holdRepository,
                                   AppointmentRepository appointmentRepository,
                                   AppointmentAuditRepository auditRepository,
                                   OutboxEventRepository outboxEventRepository,
                                   IdempotencyKeyRepository idempotencyKeyRepository,
                                   ObjectMapper objectMapper,
                                   TransactionTemplate transactionTemplate,
                                   @Value("${mediqueue.hold.expiration-max-per-scan:1000}") int maxHoldsPerScan,
                                   @Value("${mediqueue.loadtest.hold-expiration-enabled:true}") boolean holdExpirationEnabled) {
        this.holdRepository = holdRepository;
        this.appointmentRepository = appointmentRepository;
        this.auditRepository = auditRepository;
        this.outboxEventRepository = outboxEventRepository;
        this.idempotencyKeyRepository = idempotencyKeyRepository;
        this.objectMapper = objectMapper;
        this.transactionTemplate = transactionTemplate;
        this.maxHoldsPerScan = maxHoldsPerScan;
        this.holdExpirationEnabled = holdExpirationEnabled;
    }

    /**
     * Scans for active holds whose TTL has expired and transitions them.
     *
     * <p>Runs on a fixed delay configured via
     * {@code mediqueue.hold.expiration-scan-seconds} (default: 30 seconds).</p>
     */
    @Scheduled(fixedDelayString = "${mediqueue.hold.expiration-scan-seconds:30}000")
    public void expireHolds() {
        if (!holdExpirationEnabled) {
            log.debug("hold_expiration_skipped reason=disabled_for_loadtest");
            return;
        }
        for (int i = 0; i < maxHoldsPerScan; i++) {
            try {
                Optional<ExpiredHoldResult> result = transactionTemplate.execute(status -> processNextExpiredHold());
                if (result == null || result.isEmpty()) {
                    return;
                }
                log.info("hold_expired holdId={} appointmentId={}",
                        result.get().holdId(), result.get().appointmentId());
            } catch (Exception ex) {
                log.error("hold_expiration_failed", ex);
            }
        }
    }

    private Optional<ExpiredHoldResult> processNextExpiredHold() {
        Optional<AppointmentHold> holdToExpire = holdRepository.findNextExpiredHoldForUpdateSkipLocked(
                HoldStatus.ACTIVE.name(), Instant.now());
        if (holdToExpire.isEmpty()) {
            return Optional.empty();
        }

        AppointmentHold hold = holdToExpire.get();
        if (hold.getHoldStatus() != HoldStatus.ACTIVE || hold.getExpiresAt().isAfter(Instant.now())) {
            return Optional.empty();
        }

        hold.setHoldStatus(HoldStatus.EXPIRED);
        hold.setReleasedAt(Instant.now());
        holdRepository.save(hold);

        Appointment appointment = hold.getAppointment();
        if (appointment.getAppointmentStatus() != AppointmentStatus.PENDING_PAYMENT) {
            return Optional.of(new ExpiredHoldResult(hold.getHoldId(), appointment.getAppointmentId()));
        }

        appointment.setAppointmentStatus(AppointmentStatus.EXPIRED);
        appointmentRepository.save(appointment);

        AppointmentAudit audit = new AppointmentAudit();
        audit.setAppointmentId(appointment.getAppointmentId());
        audit.setPreviousStatus(AppointmentStatus.PENDING_PAYMENT);
        audit.setNewStatus(AppointmentStatus.EXPIRED);
        audit.setChangeReason("Hold expirado por TTL");
        auditRepository.save(audit);

        OutboxEvent event = new OutboxEvent();
        event.setAggregateType("appointments-exchange");
        event.setAggregateId(appointment.getAppointmentId());
        event.setEventType("appointment.expired");
        event.setPublicationStatus(OutboxPublicationStatus.PENDING);

        try {
            AppointmentExpiredEvent expiredEvent = new AppointmentExpiredEvent(
                    UUID.randomUUID().toString(),
                    "APPOINTMENT_EXPIRED",
                    Instant.now().toString(),
                    new AppointmentExpiredEvent.AppointmentExpiredPayload(
                            appointment.getAppointmentId(),
                            appointment.getPatientId(),
                            appointment.getDentistId(),
                            hold.getSlotId(),
                            appointment.getAppointmentDate(),
                            appointment.getStartTime()
                    )
            );
            String payload = objectMapper.writeValueAsString(expiredEvent);
            event.setPayload(payload);
        } catch (Exception ex) {
            throw new RuntimeException("Failed to serialize appointment.expired event", ex);
        }

        outboxEventRepository.save(event);
        return Optional.of(new ExpiredHoldResult(hold.getHoldId(), appointment.getAppointmentId()));
    }

    private record ExpiredHoldResult(UUID holdId, UUID appointmentId) {
    }

    /**
     * Cleans up expired idempotency keys from the database.
     *
     * <p>Runs on a fixed delay configured via
     * {@code mediqueue.idempotency.cleanup-interval-seconds} (default: 3600 seconds).</p>
     */
    @Scheduled(fixedDelayString = "${mediqueue.idempotency.cleanup-interval-seconds:3600}000")
    public void cleanExpiredIdempotencyKeys() {
        int deleted = idempotencyKeyRepository.deleteExpiredKeys(Instant.now());
        if (deleted > 0) {
            log.info("Idempotency keys expiradas eliminadas: {}", deleted);
        }
    }

    /**
     * Deletes published outbox events older than 7 days.
     *
     * <p>Runs on a fixed delay configured via
     * {@code mediqueue.outbox.cleanup-interval-seconds} (default: 86400 seconds).</p>
     */
    @Scheduled(fixedDelayString = "${mediqueue.outbox.cleanup-interval-seconds:86400}000")
    public void cleanPublishedOutboxEvents() {
        Instant sevenDaysAgo = Instant.now().minus(7, ChronoUnit.DAYS);
        int deleted = outboxEventRepository.deletePublishedBefore(
                OutboxPublicationStatus.PUBLISHED, sevenDaysAgo);
        if (deleted > 0) {
            log.info("Outbox events publicados eliminados: {}", deleted);
        }
    }
}
