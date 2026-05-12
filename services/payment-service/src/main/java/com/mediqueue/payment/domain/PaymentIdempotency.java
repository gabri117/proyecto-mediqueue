package com.mediqueue.payment.domain;

import com.mediqueue.payment.domain.enums.IdempotencyStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Getter
@Setter
@Entity
@Table(name = "payment_idempotency")
public class PaymentIdempotency {

    @Id
    @Column(name = "payment_idempotency_id", nullable = false)
    private UUID paymentIdempotencyId;

    @Column(name = "idempotency_key", nullable = false, unique = true, length = 120)
    private String idempotencyKey;

    @Column(name = "request_hash", nullable = false, length = 128)
    private String requestHash;

    @Column(name = "payment_id")
    private UUID paymentId;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "status", nullable = false, columnDefinition = "idempotency_status")
    private IdempotencyStatus status;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @PrePersist
    void prePersist() {
        if (paymentIdempotencyId == null) {
            paymentIdempotencyId = UUID.randomUUID();
        }
        if (status == null) {
            status = IdempotencyStatus.PROCESSING;
        }
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
