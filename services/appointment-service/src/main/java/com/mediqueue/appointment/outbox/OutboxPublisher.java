package com.mediqueue.appointment.outbox;

import com.mediqueue.appointment.domain.OutboxEvent;
import com.mediqueue.appointment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.appointment.repository.OutboxEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageBuilder;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;

/**
 * Background relay that polls the outbox table and publishes pending
 * events to RabbitMQ.
 *
 * <p>Each event is processed independently — a failure on one event
 * does not prevent the remaining events from being published.</p>
 *
 * @since 0.0.1
 */
@Component
public class OutboxPublisher {

    private static final Logger log = LoggerFactory.getLogger(OutboxPublisher.class);

    private final OutboxEventRepository outboxEventRepository;
    private final RabbitTemplate rabbitTemplate;
    private final boolean publisherEnabled;
    private final int batchSize;

    public OutboxPublisher(OutboxEventRepository outboxEventRepository,
                           RabbitTemplate rabbitTemplate,
                           @Value("${mediqueue.loadtest.outbox-publisher-enabled:true}") boolean publisherEnabled,
                           @Value("${mediqueue.outbox.batch-size:50}") int batchSize) {
        this.outboxEventRepository = outboxEventRepository;
        this.rabbitTemplate = rabbitTemplate;
        this.publisherEnabled = publisherEnabled;
        this.batchSize = Math.max(1, batchSize);
    }

    /**
     * Polls for pending outbox events and publishes them to RabbitMQ.
     *
     * <p>Runs on a fixed delay configured via
     * {@code mediqueue.outbox.publish-interval-ms} (default: 1000 ms).</p>
     */
    @Scheduled(
            initialDelayString = "${mediqueue.outbox.initial-delay-ms:0}",
            fixedDelayString = "${mediqueue.outbox.publish-interval-ms:1000}")
    @Transactional
    public void publishPendingEvents() {
        if (!publisherEnabled) {
            log.debug("outbox_publish_skipped reason=disabled_for_loadtest");
            return;
        }
        List<OutboxEvent> pending = outboxEventRepository
                .findPendingForUpdateSkipLocked(OutboxPublicationStatus.PENDING.name(), batchSize);

        for (OutboxEvent event : pending) {
            try {
                Message message = MessageBuilder
                        .withBody(event.getPayload().getBytes(StandardCharsets.UTF_8))
                        .setContentType("application/json")
                        .build();
                rabbitTemplate.send(event.getAggregateType(), event.getEventType(), message);

                event.setPublicationStatus(OutboxPublicationStatus.PUBLISHED);
                event.setPublishedAt(Instant.now());
                outboxEventRepository.save(event);

                log.debug("outbox_published eventId={} type={}", event.getEventId(), event.getEventType());
            } catch (Exception ex) {
                event.setPublicationStatus(OutboxPublicationStatus.FAILED);
                outboxEventRepository.save(event);

                log.error("outbox_publish_failed eventId={} type={}", event.getEventId(), event.getEventType(), ex);
            }
        }
    }

    /**
     * Retries outbox events that previously failed to publish.
     *
     * <p>Runs on a fixed delay configured via
     * {@code mediqueue.outbox.retry-interval-seconds} (default: 30 seconds).</p>
     */
    @Scheduled(
            initialDelayString = "${mediqueue.outbox.initial-delay-ms:0}",
            fixedDelayString = "${mediqueue.outbox.retry-interval-seconds:30}000")
    @Transactional
    public void retryFailedEvents() {
        if (!publisherEnabled) {
            log.debug("outbox_retry_skipped reason=disabled_for_loadtest");
            return;
        }
        List<OutboxEvent> failedEvents = outboxEventRepository
                .findTop10ByPublicationStatusOrderByCreatedAtAsc(OutboxPublicationStatus.FAILED);

        for (OutboxEvent event : failedEvents) {
            try {
                Message message = MessageBuilder
                        .withBody(event.getPayload().getBytes(StandardCharsets.UTF_8))
                        .setContentType("application/json")
                        .build();
                rabbitTemplate.send(event.getAggregateType(), event.getEventType(), message);

                event.setPublicationStatus(OutboxPublicationStatus.PUBLISHED);
                event.setPublishedAt(Instant.now());
                outboxEventRepository.save(event);

                log.debug("outbox_retry_published eventId={}", event.getEventId());
            } catch (Exception e) {
                log.error("Reintento fallido para outbox event {}: {}",
                        event.getEventId(), e.getMessage());
            }
        }
    }
}
