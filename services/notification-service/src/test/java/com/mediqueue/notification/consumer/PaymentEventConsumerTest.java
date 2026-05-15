package com.mediqueue.notification.consumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.mediqueue.notification.service.NotificationProcessingResult;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentEventConsumerTest {

    private final NotificationService service = mock(NotificationService.class);
    private final PaymentEventConsumer consumer = new PaymentEventConsumer(service, objectMapper());
    private final Channel channel = mock(Channel.class);

    @Test
    void envelopePaymentSucceededAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_SENT);

        consumer.handlePaymentEvent(message(envelopeJson(), "payment.succeeded", 20L), channel);

        verify(service).processAndSend(any(), any(), any(), any(), eq("PAYMENT_SUCCEEDED"),
                eq("payment-service"), eq("payment.succeeded"), eq("patient@mediqueue.test"), any());
        verify(channel).basicAck(20L, false);
    }

    @Test
    void escapedJsonStringPaymentSucceededAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_SENT);
        String escapedJson = objectMapper().writeValueAsString(envelopeJson());

        consumer.handlePaymentEvent(message(escapedJson, "payment.succeeded", 21L), channel);

        verify(channel).basicAck(21L, false);
    }

    @Test
    void legacyFlatPaymentSucceededAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_SENT);

        consumer.handlePaymentEvent(message(legacyJson(), "payment.succeeded", 22L), channel);

        verify(service).processAndSend(any(), any(), any(), any(), eq("PAYMENT_SUCCEEDED"),
                eq("payment-service"), eq("payment.succeeded"), any(), any());
        verify(channel).basicAck(22L, false);
    }

    @Test
    void duplicatePaymentEventAcksMessage() throws Exception {
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.DUPLICATE);

        consumer.handlePaymentEvent(message(envelopeJson(), "payment.succeeded", 23L), channel);

        verify(channel).basicAck(23L, false);
    }

    @Test
    void invalidJsonRejectsWithoutRequeue() throws Exception {
        consumer.handlePaymentEvent(message("{not-json", "payment.succeeded", 24L), channel);

        verify(channel).basicReject(24L, false);
    }

    private Message message(String json, String routingKey, long deliveryTag) {
        MessageProperties properties = new MessageProperties();
        properties.setContentType(MessageProperties.CONTENT_TYPE_JSON);
        properties.setHeader("__TypeId__", "java.lang.String");
        properties.setReceivedExchange("payments-exchange");
        properties.setReceivedRoutingKey(routingKey);
        properties.setDeliveryTag(deliveryTag);
        return new Message(json.getBytes(StandardCharsets.UTF_8), properties);
    }

    private String envelopeJson() {
        return """
                {
                  "eventId": "%s",
                  "eventType": "PAYMENT_SUCCEEDED",
                  "occurredAt": "2026-05-15T17:59:29.866659385Z",
                  "payload": {
                    "paymentId": "%s",
                    "appointmentId": "%s",
                    "patientId": "%s",
                    "amount": 230.00,
                    "patientEmail": "patient@mediqueue.test",
                    "resolvedAt": "2026-05-15T17:59:29.864290578Z"
                  }
                }
                """.formatted(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());
    }

    private String legacyJson() {
        return """
                {
                  "eventId": "%s",
                  "eventType": "PAYMENT_SUCCEEDED",
                  "paymentId": "%s",
                  "appointmentId": "%s",
                  "patientId": "%s",
                  "amount": 230.00
                }
                """.formatted(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());
    }

    private static ObjectMapper objectMapper() {
        return new ObjectMapper().registerModule(new JavaTimeModule());
    }
}
