package com.mediqueue.appointment.messaging;

import com.mediqueue.appointment.events.consumed.PaymentSucceededEvent;
import com.mediqueue.appointment.service.AppointmentService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * Consumes {@code payment.succeeded} events from RabbitMQ and triggers
 * appointment confirmation.
 *
 * @since 0.0.1
 */
@Component
public class PaymentSucceededConsumer {

    private static final Logger log = LoggerFactory.getLogger(PaymentSucceededConsumer.class);

    private final AppointmentService appointmentService;

    public PaymentSucceededConsumer(AppointmentService appointmentService) {
        this.appointmentService = appointmentService;
    }

    /**
     * Handles a successful payment event by confirming the associated appointment.
     *
     * @param event the inbound payment succeeded event
     */
    @RabbitListener(queues = "payment.succeeded")
    public void handlePaymentSucceeded(PaymentSucceededEvent event) {
        log.info("PaymentSucceeded recibido para appointmentId: {}", event.payload().appointmentId());

        try {
            appointmentService.confirmAppointment(event.payload().appointmentId());
        } catch (Exception ex) {
            log.error("confirm_failed appointmentId={}", event.payload().appointmentId(), ex);
            throw ex;
        }
    }
}
