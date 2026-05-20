package com.mediqueue.payment.outbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.payment.config.RabbitMQConfig;
import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.payment.repository.PaymentEventsOutboxRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Component
public class PaymentOutboxPublisher {

    private final PaymentEventsOutboxRepository outboxRepository;
    private final RabbitTemplate rabbitTemplate;
    private final ObjectMapper objectMapper;
    private final int batchSize;
    private final Counter publishedCounter;
    private final Counter failedCounter;

    public PaymentOutboxPublisher(
            PaymentEventsOutboxRepository outboxRepository,
            RabbitTemplate rabbitTemplate,
            ObjectMapper objectMapper,
            MeterRegistry meterRegistry,
            @Value("${mediqueue.outbox.batch-size:50}") int batchSize) {
        this.outboxRepository = outboxRepository;
        this.rabbitTemplate = rabbitTemplate;
        this.objectMapper = objectMapper;
        this.batchSize = batchSize;
        this.publishedCounter = meterRegistry.counter("payment.outbox.published.total");
        this.failedCounter = meterRegistry.counter("payment.outbox.failed.total");
    }

    @Transactional
    @Scheduled(fixedDelayString = "${mediqueue.outbox.publish-interval-ms:1000}")
    public void publishPendingEvents() {
        List<PaymentEventsOutbox> events = outboxRepository.findPendingForUpdateSkipLocked(batchSize);
        for (PaymentEventsOutbox event : events) {
            try {
                Object payloadObject = objectMapper.readValue(event.getPayload(), Object.class);
                rabbitTemplate.convertAndSend(
                        RabbitMQConfig.PAYMENTS_EXCHANGE,
                        routingKey(event.getEventType()),
                        payloadObject);
                event.setPublicationStatus(OutboxPublicationStatus.PUBLISHED);
                event.setPublishedAt(LocalDateTime.now(ZoneOffset.UTC));
                outboxRepository.save(event);
                publishedCounter.increment();
            } catch (Exception ex) {
                failedCounter.increment();
                log.error("Failed to publish outbox event {}", event.getEventId(), ex);
            }
        }
    }

    private String routingKey(String eventType) {
        return switch (eventType) {
            case "PAYMENT_SUCCEEDED" -> RabbitMQConfig.PAYMENT_SUCCEEDED_ROUTING_KEY;
            case "PAYMENT_FAILED" -> RabbitMQConfig.PAYMENT_FAILED_ROUTING_KEY;
            default -> throw new IllegalArgumentException("Unsupported outbox event type: " + eventType);
        };
    }
}
