package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.AppointmentHold;
import com.mediqueue.appointment.domain.enums.HoldStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Spring Data JPA repository for {@link AppointmentHold} entities.
 *
 * @since 0.0.1
 */
public interface AppointmentHoldRepository extends JpaRepository<AppointmentHold, UUID> {

    /**
     * Finds a hold for a specific slot with a given status.
     *
     * @param slotId     the slot's unique identifier
     * @param holdStatus the hold status to filter by
     * @return the matching hold, if any
     */
    Optional<AppointmentHold> findBySlotIdAndHoldStatus(UUID slotId, HoldStatus holdStatus);

    /**
     * Finds all holds with a given status that have expired before the specified instant.
     * Used by the scheduler that releases stale holds.
     *
     * @param holdStatus the status to filter by (typically {@code ACTIVE})
     * @param now        the reference instant for expiration comparison
     * @return list of expired holds
     */
    List<AppointmentHold> findByHoldStatusAndExpiresAtBefore(HoldStatus holdStatus, Instant now);
}
