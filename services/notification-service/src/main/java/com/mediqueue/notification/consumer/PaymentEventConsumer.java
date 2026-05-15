package com.mediqueue.notification.consumer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.notification.config.RabbitMQConfig;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.events.EventEnvelope;
import com.mediqueue.notification.events.PaymentEventPayload;
import com.mediqueue.notification.service.NonRetryableNotificationException;
import com.mediqueue.notification.service.NotificationProcessingResult;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

@Slf4j
@Component
@RequiredArgsConstructor
public class PaymentEventConsumer {

    private final NotificationService notificationService;
    private final ObjectMapper objectMapper;

    @RabbitListener(
            queues = "${notification.rabbitmq.payment-queue:" + RabbitMQConfig.QUEUE_NOTIFICATION_PAYMENT + "}",
            containerFactory = "rabbitListenerContainerFactory"
    )
    public void handlePaymentEvent(Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        String routingKey = message.getMessageProperties().getReceivedRoutingKey();
        PaymentEventMessage event;
        try {
            event = parsePaymentEvent(message);
        } catch (JsonProcessingException | IllegalArgumentException ex) {
            log.warn("payment_event_rejected_invalid_json routingKey={} reason={}", routingKey, ex.getMessage());
            channel.basicReject(deliveryTag, false);
            return;
        }

        log.info("payment_event_received eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={}",
                event.eventType(), event.eventId(), event.payload().getPaymentId(),
                event.payload().getAppointmentId(), event.payload().getPatientId(), routingKey);

        try {
            NotificationProcessingResult result = notificationService.processAndSend(
                    event.payload().getPatientId(),
                    event.payload().getAppointmentId(),
                    event.payload().getPaymentId(),
                    event.eventIdAsString(),
                    event.eventType(),
                    "payment-service",
                    routingKey,
                    resolveDestination(event),
                    NotificationChannel.EMAIL
            );
            log.info("payment_event_processed eventType={} eventId={} result={} paymentId={} appointmentId={} patientId={} routingKey={}",
                    event.eventType(), event.eventId(), result, event.payload().getPaymentId(),
                    event.payload().getAppointmentId(), event.payload().getPatientId(), routingKey);
            channel.basicAck(deliveryTag, false);
        } catch (NonRetryableNotificationException | AmqpRejectAndDontRequeueException ex) {
            log.warn("payment_event_rejected eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={} reason={}",
                    event.eventType(), event.eventId(), event.payload().getPaymentId(),
                    event.payload().getAppointmentId(), event.payload().getPatientId(), routingKey, ex.getMessage());
            channel.basicReject(deliveryTag, false);
        } catch (DataAccessException ex) {
            log.error("payment_event_persistence_error eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={} requeue={}",
                    event.eventType(), event.eventId(), event.payload().getPaymentId(),
                    event.payload().getAppointmentId(), event.payload().getPatientId(), routingKey, false, ex);
            channel.basicNack(deliveryTag, false, false);
        } catch (Exception ex) {
            log.error("payment_event_unexpected_error eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={}",
                    event.eventType(), event.eventId(), event.payload().getPaymentId(),
                    event.payload().getAppointmentId(), event.payload().getPatientId(), routingKey, ex);
            channel.basicReject(deliveryTag, false);
        }
    }

    private PaymentEventMessage parsePaymentEvent(Message message) throws JsonProcessingException {
        JsonNode root = readRoot(message);
        String routingKey = message.getMessageProperties().getReceivedRoutingKey();
        boolean envelopeFormat = root.hasNonNull("payload") && root.get("payload").isObject();
        EventEnvelope<JsonNode> envelope = envelopeFormat
                ? objectMapper.convertValue(root, new TypeReference<EventEnvelope<JsonNode>>() {
                })
                : null;
        JsonNode payloadNode = envelopeFormat ? envelope.getPayload() : root;
        PaymentEventPayload payload = objectMapper.treeToValue(payloadNode, PaymentEventPayload.class);
        UUID eventId = envelopeFormat ? envelope.getEventId() : uuid(root.path("eventId").asText(null));
        String eventType = envelopeFormat ? envelope.getEventType() : root.path("eventType").asText(null);
        if (!StringUtils.hasText(eventType)) {
            eventType = eventTypeFromRoutingKey(routingKey);
        }
        return new PaymentEventMessage(eventId, eventType, payload);
    }

    private JsonNode readRoot(Message message) throws JsonProcessingException {
        String rawJson = new String(message.getBody(), StandardCharsets.UTF_8);
        JsonNode root = objectMapper.readTree(rawJson);
        if (root.isTextual()) {
            return objectMapper.readTree(root.asText());
        }
        return root;
    }

    private String eventTypeFromRoutingKey(String routingKey) {
        if ("payment.failed".equals(routingKey)) {
            return "PAYMENT_FAILED";
        }
        return "PAYMENT_SUCCEEDED";
    }

    private UUID uuid(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        return UUID.fromString(value);
    }

    private String resolveDestination(PaymentEventMessage event) {
        if (StringUtils.hasText(event.payload().getPatientEmail())) {
            return event.payload().getPatientEmail();
        }
        return "patient-" + event.payload().getPatientId() + "@mediqueue.test";
    }

    private record PaymentEventMessage(UUID eventId, String eventType, PaymentEventPayload payload) {
        String eventIdAsString() {
            return eventId == null ? null : eventId.toString();
        }
    }
}
