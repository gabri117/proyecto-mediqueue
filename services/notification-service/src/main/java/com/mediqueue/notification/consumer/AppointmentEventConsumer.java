package com.mediqueue.notification.consumer;

import com.mediqueue.notification.config.RabbitMQConfig;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.events.AppointmentEvent;
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
public class AppointmentEventConsumer {

    private final NotificationService notificationService;

    @RabbitListener(
            queues = "${notification.rabbitmq.appointment-queue:" + RabbitMQConfig.QUEUE_NOTIFICATION_APPOINTMENT + "}",
            containerFactory = "rabbitListenerContainerFactory"
    )
    public void handleAppointmentEvent(
            AppointmentEvent event,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            @Header(name = AmqpHeaders.RECEIVED_ROUTING_KEY, required = false) String routingKey,
            @Header(name = AmqpHeaders.REDELIVERED, required = false) Boolean redelivered
    ) throws IOException {
        log.info("appointment_event_received eventType={} eventId={} appointmentId={} patientId={} routingKey={}",
                event.effectiveEventType(), event.getEventId(), event.effectiveAppointmentId(),
                event.effectivePatientId(), routingKey);

        try {
            NotificationProcessingResult result = notificationService.processAndSend(
                    event.effectivePatientId(),
                    event.effectiveAppointmentId(),
                    null,
                    event.getEventId(),
                    event.effectiveEventType(),
                    "appointment-service",
                    routingKey,
                    resolveDestination(event),
                    NotificationChannel.EMAIL
            );
            log.info("appointment_event_processed eventType={} eventId={} result={} appointmentId={} patientId={} routingKey={}",
                    event.effectiveEventType(), event.getEventId(), result,
                    event.effectiveAppointmentId(), event.effectivePatientId(), routingKey);
            channel.basicAck(deliveryTag, false);
        } catch (NonRetryableNotificationException | AmqpRejectAndDontRequeueException ex) {
            log.warn("appointment_event_rejected eventType={} eventId={} appointmentId={} patientId={} routingKey={} reason={}",
                    event.effectiveEventType(), event.getEventId(), event.effectiveAppointmentId(),
                    event.effectivePatientId(), routingKey, ex.getMessage());
            channel.basicReject(deliveryTag, false);
        } catch (DataAccessException ex) {
            boolean requeue = !Boolean.TRUE.equals(redelivered);
            log.error("appointment_event_persistence_error eventType={} eventId={} appointmentId={} patientId={} routingKey={} requeue={}",
                    event.effectiveEventType(), event.getEventId(), event.effectiveAppointmentId(),
                    event.effectivePatientId(), routingKey, requeue, ex);
            channel.basicNack(deliveryTag, false, requeue);
        } catch (Exception ex) {
            log.error("appointment_event_unexpected_error eventType={} eventId={} appointmentId={} patientId={} routingKey={}",
                    event.effectiveEventType(), event.getEventId(), event.effectiveAppointmentId(),
                    event.effectivePatientId(), routingKey, ex);
            channel.basicReject(deliveryTag, false);
        }
    }

    private String resolveDestination(AppointmentEvent event) {
        if (event.getPatientEmail() != null && !event.getPatientEmail().isBlank()) {
            return event.getPatientEmail();
        }
        return "patient-" + event.effectivePatientId() + "@mediqueue.test";
    }
}
