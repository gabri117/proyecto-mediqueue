package com.mediqueue.notification.consumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.mediqueue.notification.service.NonRetryableNotificationException;
import com.mediqueue.notification.service.NotificationProcessingResult;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AppointmentEventConsumerTest {

    private final NotificationService service = mock(NotificationService.class);
    private final AppointmentEventConsumer consumer = new AppointmentEventConsumer(service, objectMapper());
    private final Channel channel = mock(Channel.class);

    @Test
    void envelopeEventAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_SENT);

        consumer.handleAppointmentEvent(message(envelopeJson(), "appointment.confirmed", 10L), channel);

        verify(channel).basicAck(10L, false);
    }

    @Test
    void duplicateEventAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.DUPLICATE);

        consumer.handleAppointmentEvent(message(envelopeJson(), "appointment.confirmed", 11L), channel);

        verify(channel).basicAck(11L, false);
    }

    @Test
    void controlledFailedNotificationAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_FAILED);

        consumer.handleAppointmentEvent(message(envelopeJson(), "appointment.cancelled", 12L), channel);

        verify(channel).basicAck(12L, false);
    }

    @Test
    void irreversibleValidationRejectsWithoutRequeue() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new NonRetryableNotificationException("patientId is required"));

        consumer.handleAppointmentEvent(message(envelopeJson(), "appointment.confirmed", 13L), channel);

        verify(channel).basicReject(13L, false);
    }

    @Test
    void invalidJsonRejectsWithoutMessageConversionFailure() throws Exception {
        consumer.handleAppointmentEvent(message("{not-json", "appointment.confirmed", 14L), channel);

        verify(channel).basicReject(14L, false);
    }

    private Message message(String json, String routingKey, long deliveryTag) {
        MessageProperties properties = new MessageProperties();
        properties.setContentType(MessageProperties.CONTENT_TYPE_JSON);
        properties.setReceivedExchange("appointments-exchange");
        properties.setReceivedRoutingKey(routingKey);
        properties.setDeliveryTag(deliveryTag);
        return new Message(json.getBytes(StandardCharsets.UTF_8), properties);
    }

    private String envelopeJson() {
        return """
                {
                  "eventId": "%s",
                  "eventType": "APPOINTMENT_CONFIRMED",
                  "occurredAt": "2026-05-15T17:59:29.866659385Z",
                  "payload": {
                    "appointmentId": "%s",
                    "patientId": "%s",
                    "slotId": "%s",
                    "appointmentStatus": "CONFIRMED",
                    "patientEmail": "patient@mediqueue.test",
                    "amount": 230.00
                  }
                }
                """.formatted(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());
    }

    private static ObjectMapper objectMapper() {
        return new ObjectMapper().registerModule(new JavaTimeModule());
    }
}
