package com.mediqueue.notification.consumer;

import com.mediqueue.notification.config.RabbitMQConfig;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.events.PaymentEvent;
import com.mediqueue.notification.service.NonRetryableNotificationException;
import com.mediqueue.notification.service.NotificationProcessingResult;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.dao.DataAccessException;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Slf4j
@Component
@RequiredArgsConstructor
public class PaymentEventConsumer {

    private final NotificationService notificationService;

    @RabbitListener(
            queues = "${notification.rabbitmq.payment-queue:" + RabbitMQConfig.QUEUE_NOTIFICATION_PAYMENT + "}",
            containerFactory = "rabbitListenerContainerFactory"
    )
    public void handlePaymentEvent(
            PaymentEvent event,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            @Header(name = AmqpHeaders.RECEIVED_ROUTING_KEY, required = false) String routingKey,
            @Header(name = AmqpHeaders.REDELIVERED, required = false) Boolean redelivered
    ) throws IOException {
        log.info("payment_event_received eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={}",
                event.getEventType(), event.getEventId(), event.effectivePaymentId(),
                event.effectiveAppointmentId(), event.effectivePatientId(), routingKey);

        try {
            NotificationProcessingResult result = notificationService.processAndSend(
                    event.effectivePatientId(),
                    event.effectiveAppointmentId(),
                    event.effectivePaymentId(),
                    event.getEventId(),
                    event.getEventType(),
                    "payment-service",
                    routingKey,
                    resolveDestination(event),
                    NotificationChannel.EMAIL
            );
            log.info("payment_event_processed eventType={} eventId={} result={} paymentId={} appointmentId={} patientId={} routingKey={}",
                    event.getEventType(), event.getEventId(), result, event.effectivePaymentId(),
                    event.effectiveAppointmentId(), event.effectivePatientId(), routingKey);
            channel.basicAck(deliveryTag, false);
        } catch (NonRetryableNotificationException | AmqpRejectAndDontRequeueException ex) {
            log.warn("payment_event_rejected eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={} reason={}",
                    event.getEventType(), event.getEventId(), event.effectivePaymentId(),
                    event.effectiveAppointmentId(), event.effectivePatientId(), routingKey, ex.getMessage());
            channel.basicReject(deliveryTag, false);
        } catch (DataAccessException ex) {
            boolean requeue = !Boolean.TRUE.equals(redelivered);
            log.error("payment_event_persistence_error eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={} requeue={}",
                    event.getEventType(), event.getEventId(), event.effectivePaymentId(),
                    event.effectiveAppointmentId(), event.effectivePatientId(), routingKey, requeue, ex);
            channel.basicNack(deliveryTag, false, requeue);
        } catch (Exception ex) {
            log.error("payment_event_unexpected_error eventType={} eventId={} paymentId={} appointmentId={} patientId={} routingKey={}",
                    event.getEventType(), event.getEventId(), event.effectivePaymentId(),
                    event.effectiveAppointmentId(), event.effectivePatientId(), routingKey, ex);
            channel.basicReject(deliveryTag, false);
        }
    }

    private String resolveDestination(PaymentEvent event) {
        if (event.getPatientEmail() != null && !event.getPatientEmail().isBlank()) {
            return event.getPatientEmail();
        }
        return "patient-" + event.effectivePatientId() + "@mediqueue.test";
    }
}
