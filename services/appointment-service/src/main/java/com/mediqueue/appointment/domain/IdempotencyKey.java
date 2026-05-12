package com.mediqueue.appointment.domain;

import com.mediqueue.appointment.domain.enums.IdempotencyStatus;
import jakarta.persistence.Column;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapped to the {@code idempotency_keys} table.
 *
 * <p>Stores idempotency keys sent by clients via the
 * {@code X-Idempotency-Key} header. If a key already exists with
 * {@code SUCCEEDED} status, the cached response is returned instead
 * of re-processing the operation.</p>
 *
 * @since 0.0.1
 */
@Entity
@Table(name = "idempotency_keys")
@Getter
@Setter
@NoArgsConstructor
public class IdempotencyKey {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "idempotency_id", updatable = false, nullable = false)
    private UUID idempotencyId;

    @Column(name = "operation_type", nullable = false, length = 50)
    private String operationType;

    @Column(name = "idempotency_key", nullable = false, length = 120)
    private String idempotencyKey;

    @Column(name = "request_hash", nullable = false, length = 128)
    private String requestHash;

    @Column(name = "response_reference", length = 120)
    private String responseReference;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private IdempotencyStatus status = IdempotencyStatus.PROCESSING;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;
}
