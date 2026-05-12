package com.mediqueue.notification.consumer;

import com.mediqueue.notification.config.RabbitMQConfig;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.events.AppointmentEvent;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Slf4j
@Component
@RequiredArgsConstructor
public class AppointmentEventConsumer {

    private final NotificationService notificationService;

    @RabbitListener(
            queues = RabbitMQConfig.QUEUE_NOTIFICATION_APPOINTMENT,
            containerFactory = "rabbitListenerContainerFactory"
    )
    public void handleAppointmentEvent(
            AppointmentEvent event,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag
    ) throws IOException {
        log.info("Evento de cita recibido: tipo={} appointmentId={} patientId={}",
                event.getEventType(), event.getAppointmentId(), event.getPatientId());

        try {
            String destination = resolveDestination(event);
            notificationService.processAndSend(
                    event.getPatientId(),
                    event.getAppointmentId(),
                    event.getEventType(),
                    destination,
                    NotificationChannel.EMAIL
            );
            channel.basicAck(deliveryTag, false);
        } catch (Exception ex) {
            log.error("Error procesando evento de cita tipo={} id={}: {}",
                    event.getEventType(), event.getAppointmentId(), ex.getMessage());
            // Ack igual para evitar requeue infinito (best-effort por diseño — RN-NOT-02)
            channel.basicAck(deliveryTag, false);
        }
    }

    private String resolveDestination(AppointmentEvent event) {
        if (event.getPatientEmail() != null && !event.getPatientEmail().isBlank()) {
            return event.getPatientEmail();
        }
        // Fallback: destino simulado cuando el evento no trae email
        return "patient-" + event.getPatientId() + "@mediqueue.test";
    }
}
