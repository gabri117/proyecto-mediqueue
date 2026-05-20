package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.OutboxEvent;
import com.mediqueue.appointment.domain.enums.OutboxPublicationStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Spring Data JPA repository for {@link OutboxEvent} entities.
 *
 * @since 0.0.1
 */
public interface OutboxEventRepository extends JpaRepository<OutboxEvent, UUID> {

    /**
     * Retrieves up to 50 outbox events with the given publication status,
     * ordered by creation time ascending (FIFO). Used by the background
     * relay that publishes pending events to RabbitMQ.
     *
     * @param status the publication status to filter by (typically {@code PENDING})
     * @return ordered list of events ready for publication
     */
    List<OutboxEvent> findTop50ByPublicationStatusOrderByCreatedAtAsc(OutboxPublicationStatus status);

    /**
     * Claims pending outbox events with PostgreSQL row locking. Multiple
     * appointment-service replicas can run the publisher concurrently without
     * blocking each other or publishing the same event twice.
     *
     * @param status pending status value stored in the database
     * @return locked events ready for publication
     */
    @Query(value = """
            SELECT *
            FROM outbox_events
            WHERE publication_status = :status
            ORDER BY created_at
            LIMIT :limit
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    List<OutboxEvent> findPendingForUpdateSkipLocked(@Param("status") String status,
                                                      @Param("limit") int limit);

    /**
     * Retrieves up to 10 outbox events with the given publication status,
     * ordered by creation time ascending. Used by the retry job.
     *
     * @param status the publication status to filter by (typically {@code FAILED})
     * @return ordered list of events to retry
     */
    List<OutboxEvent> findTop10ByPublicationStatusOrderByCreatedAtAsc(OutboxPublicationStatus status);

    /**
     * Deletes published outbox events older than the given threshold.
     *
     * @param status the publication status to match (typically {@code PUBLISHED})
     * @param before the cutoff instant; events published before this are deleted
     * @return number of records deleted
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM OutboxEvent oe WHERE oe.publicationStatus = :status AND oe.publishedAt < :before")
    int deletePublishedBefore(@Param("status") OutboxPublicationStatus status,
                              @Param("before") Instant before);
}
