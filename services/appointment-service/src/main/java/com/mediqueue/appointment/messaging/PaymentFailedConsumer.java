package com.mediqueue.appointment.messaging;

import com.mediqueue.appointment.events.consumed.PaymentFailedEvent;
import com.mediqueue.appointment.service.AppointmentService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * Consumes {@code payment.failed} events from RabbitMQ and triggers
 * appointment cancellation as compensation.
 *
 * @since 0.0.1
 */
@Component
public class PaymentFailedConsumer {

    private static final Logger log = LoggerFactory.getLogger(PaymentFailedConsumer.class);

    private final AppointmentService appointmentService;

    public PaymentFailedConsumer(AppointmentService appointmentService) {
        this.appointmentService = appointmentService;
    }

    /**
     * Handles a failed payment event by cancelling the associated appointment.
     *
     * @param event the inbound payment failed event
     */
    @RabbitListener(queues = "payment.failed")
    public void handlePaymentFailed(PaymentFailedEvent event) {
        log.info("PaymentFailed recibido para appointmentId: {}", event.payload().appointmentId());

        try {
            appointmentService.compensateAppointment(event.payload().appointmentId());
        } catch (Exception ex) {
            log.error("compensate_failed appointmentId={}", event.payload().appointmentId(), ex);
            throw ex;
        }
    }
}
