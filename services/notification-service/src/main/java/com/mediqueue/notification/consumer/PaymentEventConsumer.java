package com.mediqueue.notification.consumer;

import com.mediqueue.notification.config.RabbitMQConfig;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.events.PaymentEvent;
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
public class PaymentEventConsumer {

    private final NotificationService notificationService;

    @RabbitListener(
            queues = RabbitMQConfig.QUEUE_NOTIFICATION_PAYMENT,
            containerFactory = "rabbitListenerContainerFactory"
    )
    public void handlePaymentEvent(
            PaymentEvent event,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag
    ) throws IOException {
        log.info("Evento de pago recibido: tipo={} paymentId={} appointmentId={}",
                event.getEventType(), event.getPaymentId(), event.getAppointmentId());

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
            log.error("Error procesando evento de pago tipo={} id={}: {}",
                    event.getEventType(), event.getPaymentId(), ex.getMessage());
            // Ack igual — best-effort por diseño (RN-NOT-02)
            channel.basicAck(deliveryTag, false);
        }
    }

    private String resolveDestination(PaymentEvent event) {
        if (event.getPatientEmail() != null && !event.getPatientEmail().isBlank()) {
            return event.getPatientEmail();
        }
        return "patient-" + event.getPatientId() + "@mediqueue.test";
    }
}
