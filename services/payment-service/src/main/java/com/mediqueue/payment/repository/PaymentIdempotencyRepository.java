package com.mediqueue.payment.repository;

import com.mediqueue.payment.domain.PaymentIdempotency;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PaymentIdempotencyRepository extends JpaRepository<PaymentIdempotency, UUID> {

    Optional<PaymentIdempotency> findByIdempotencyKey(String idempotencyKey);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from PaymentIdempotency p where p.idempotencyKey = :key")
    Optional<PaymentIdempotency> findByIdempotencyKeyForUpdate(@Param("key") String key);
}
