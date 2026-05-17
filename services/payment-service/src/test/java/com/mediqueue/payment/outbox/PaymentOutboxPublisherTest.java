package com.mediqueue.payment.outbox;

import com.mediqueue.payment.config.RabbitMQConfig;
import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.payment.repository.PaymentEventsOutboxRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentOutboxPublisherTest {

    @Test
    void leavesEventPendingWhenRabbitMqFails() {
        PaymentEventsOutboxRepository repository = mock(PaymentEventsOutboxRepository.class);
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        PaymentEventsOutbox event = new PaymentEventsOutbox();
        event.setEventId(UUID.randomUUID());
        event.setPaymentId(UUID.randomUUID());
        event.setEventType("PAYMENT_SUCCEEDED");
        event.setPayload("{}");
        event.setPublicationStatus(OutboxPublicationStatus.PENDING);
        when(repository.findPendingForUpdateSkipLocked(50)).thenReturn(List.of(event));
        doThrow(new RuntimeException("RabbitMQ down"))
                .when(rabbitTemplate)
                .convertAndSend(any(String.class), any(String.class), any(Object.class));

        PaymentOutboxPublisher publisher = new PaymentOutboxPublisher(repository, rabbitTemplate, new SimpleMeterRegistry(), 50);
        publisher.publishPendingEvents();

        assertThat(event.getPublicationStatus()).isEqualTo(OutboxPublicationStatus.PENDING);
    }

    @Test
    void concurrentPublishersProcessDistinctLockedBatches() throws Exception {
        PaymentEventsOutboxRepository repository = mock(PaymentEventsOutboxRepository.class);
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        Queue<List<PaymentEventsOutbox>> lockedBatches = new ArrayDeque<>();
        PaymentEventsOutbox first = pendingEvent("PAYMENT_SUCCEEDED", "payload-1");
        PaymentEventsOutbox second = pendingEvent("PAYMENT_FAILED", "payload-2");
        lockedBatches.add(List.of(first));
        lockedBatches.add(List.of(second));

        when(repository.findPendingForUpdateSkipLocked(1)).thenAnswer(invocation -> {
            synchronized (lockedBatches) {
                return lockedBatches.isEmpty() ? List.of() : lockedBatches.remove();
            }
        });

        PaymentOutboxPublisher firstPublisher = new PaymentOutboxPublisher(repository, rabbitTemplate, new SimpleMeterRegistry(), 1);
        PaymentOutboxPublisher secondPublisher = new PaymentOutboxPublisher(repository, rabbitTemplate, new SimpleMeterRegistry(), 1);
        CountDownLatch start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(2);
        List<Runnable> tasks = List.of(firstPublisher::publishPendingEvents, secondPublisher::publishPendingEvents);
        List<java.util.concurrent.Future<?>> futures = new ArrayList<>();
        for (Runnable task : tasks) {
            futures.add(executor.submit(() -> {
                start.await();
                task.run();
                return null;
            }));
        }

        start.countDown();
        for (var future : futures) {
            future.get();
        }
        executor.shutdown();

        assertThat(first.getPublicationStatus()).isEqualTo(OutboxPublicationStatus.PUBLISHED);
        assertThat(second.getPublicationStatus()).isEqualTo(OutboxPublicationStatus.PUBLISHED);
        verify(rabbitTemplate).convertAndSend(
                eq(RabbitMQConfig.PAYMENTS_EXCHANGE),
                eq(RabbitMQConfig.PAYMENT_SUCCEEDED_ROUTING_KEY),
                eq("payload-1"));
        verify(rabbitTemplate).convertAndSend(
                eq(RabbitMQConfig.PAYMENTS_EXCHANGE),
                eq(RabbitMQConfig.PAYMENT_FAILED_ROUTING_KEY),
                eq("payload-2"));
        verify(repository, times(2)).save(any(PaymentEventsOutbox.class));
    }

    private PaymentEventsOutbox pendingEvent(String eventType, String payload) {
        PaymentEventsOutbox event = new PaymentEventsOutbox();
        event.setEventId(UUID.randomUUID());
        event.setPaymentId(UUID.randomUUID());
        event.setEventType(eventType);
        event.setPayload(payload);
        event.setPublicationStatus(OutboxPublicationStatus.PENDING);
        return event;
    }
}
