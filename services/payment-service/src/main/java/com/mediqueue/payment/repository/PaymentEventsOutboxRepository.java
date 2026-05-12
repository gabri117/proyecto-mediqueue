package com.mediqueue.payment.repository;

import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.enums.OutboxPublicationStatus;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PaymentEventsOutboxRepository extends JpaRepository<PaymentEventsOutbox, UUID> {

    @Query(
            value = """
                    SELECT * FROM payment_events_outbox
                    WHERE publication_status = 'PENDING'
                    ORDER BY created_at
                    LIMIT :limit
                    FOR UPDATE SKIP LOCKED
                    """,
            nativeQuery = true)
    List<PaymentEventsOutbox> findPendingForUpdateSkipLocked(@Param("limit") int limit);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    List<PaymentEventsOutbox> findByPublicationStatusOrderByCreatedAtAsc(OutboxPublicationStatus status);
}
