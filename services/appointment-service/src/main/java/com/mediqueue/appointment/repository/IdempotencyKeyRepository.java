package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.IdempotencyKey;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Spring Data JPA repository for {@link IdempotencyKey} entities.
 *
 * @since 0.0.1
 */
public interface IdempotencyKeyRepository extends JpaRepository<IdempotencyKey, UUID> {

    /**
     * Looks up an existing idempotency record by operation type and client-provided key.
     *
     * @param operationType  the type of operation (e.g. {@code "CREATE_APPOINTMENT"})
     * @param idempotencyKey the client-supplied idempotency key
     * @return the matching record, if any
     */
    Optional<IdempotencyKey> findByOperationTypeAndIdempotencyKey(String operationType, String idempotencyKey);

    /**
     * Deletes all idempotency keys whose expiration timestamp is before the given instant.
     *
     * @param now the cutoff instant
     * @return number of records deleted
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM IdempotencyKey ik WHERE ik.expiresAt < :now")
    int deleteExpiredKeys(@Param("now") Instant now);
}
