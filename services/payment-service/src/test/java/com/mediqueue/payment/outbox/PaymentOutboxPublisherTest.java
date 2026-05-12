package com.mediqueue.payment.outbox;

import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.payment.repository.PaymentEventsOutboxRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
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
}
