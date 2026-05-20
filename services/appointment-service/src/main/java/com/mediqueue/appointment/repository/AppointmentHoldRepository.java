package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.AppointmentHold;
import com.mediqueue.appointment.domain.enums.HoldStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

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

    /**
     * Claims one expired hold using PostgreSQL row locking so multiple
     * appointment-service replicas do not process the same hold concurrently.
     *
     * <p>The query intentionally uses {@code SKIP LOCKED}: if another replica
     * is already working on a hold, this scheduler instance moves to another
     * candidate instead of blocking the scan.</p>
     *
     * @param holdStatus active status value stored in the database
     * @param now        the reference instant for expiration comparison
     * @return one locked expired hold, if any
     */
    @Query(value = """
            SELECT *
            FROM appointment_holds
            WHERE hold_status = :holdStatus
              AND expires_at < :now
            ORDER BY expires_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    Optional<AppointmentHold> findNextExpiredHoldForUpdateSkipLocked(@Param("holdStatus") String holdStatus,
                                                                     @Param("now") Instant now);
}
