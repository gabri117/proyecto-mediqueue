package com.mediqueue.schedule.messaging.consumer;

import com.mediqueue.schedule.messaging.events.AppointmentConfirmedEvent;
import com.mediqueue.schedule.messaging.events.AppointmentHeldEvent;
import com.mediqueue.schedule.messaging.events.AppointmentReleasedEvent;
import com.mediqueue.schedule.messaging.service.SlotStatusUpdateService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * RabbitMQ consumer that keeps the slot display status in schedule-service
 * synchronized with the appointment lifecycle events published by
 * appointment-service.
 *
 * <h3>Routing key → slot state transitions:</h3>
 * <pre>
 *   appointment.held      → HELD
 *   appointment.confirmed → BOOKED
 *   appointment.cancelled → AVAILABLE
 *   appointment.expired   → AVAILABLE
 * </pre>
 *
 * <h3>Idempotency</h3>
 * <p>All transitions are delegated to {@link SlotStatusUpdateService}, which
 * applies them only when the current state allows it. Duplicate deliveries
 * of the same event are silently discarded.</p>
 *
 * <h3>Error handling</h3>
 * <p>If the slot is not found, the event is logged as a warning and ACK'd
 * immediately — this avoids indefinitely blocking the queue with an event
 * that can never be processed. Any other runtime exception bubbles up,
 * triggering the retry policy configured in {@code application.properties}
 * (3 attempts with exponential backoff), and then the message is sent to
 * the DLQ.</p>
 *
 * @since 0.0.2
 */
@Component
@RequiredArgsConstructor
public class AppointmentEventConsumer {

    private static final Logger log = LoggerFactory.getLogger(AppointmentEventConsumer.class);

    private final SlotStatusUpdateService slotStatusUpdateService;

    /**
     * Listens for {@code appointment.held} events and marks the slot as HELD.
     */
    @RabbitListener(queues = "schedule.appointment.held")
    public void onAppointmentHeld(AppointmentHeldEvent event) {
        if (event.payload() == null || event.payload().slotId() == null) {
            log.warn("appointment_held_missing_slot_id eventId={}", event.eventId());
            return;
        }

        log.info("appointment_held_received eventId={} appointmentId={} slotId={}",
                event.eventId(), event.payload().appointmentId(), event.payload().slotId());

        slotStatusUpdateService.markHeld(event.payload().slotId(), event.payload().appointmentId());
    }

    /**
     * Listens for {@code appointment.confirmed} events and marks the slot as BOOKED.
     */
    @RabbitListener(queues = "schedule.appointment.confirmed")
    public void onAppointmentConfirmed(AppointmentConfirmedEvent event) {
        if (event.payload() == null || event.payload().slotId() == null) {
            log.warn("appointment_confirmed_missing_slot_id eventId={}", event.eventId());
            return;
        }

        log.info("appointment_confirmed_received eventId={} appointmentId={} slotId={}",
                event.eventId(), event.payload().appointmentId(), event.payload().slotId());

        slotStatusUpdateService.markBooked(event.payload().slotId(), event.payload().appointmentId());
    }

    /**
     * Listens for {@code appointment.cancelled} events and releases the slot back to AVAILABLE.
     */
    @RabbitListener(queues = "schedule.appointment.cancelled")
    public void onAppointmentCancelled(AppointmentReleasedEvent event) {
        if (event.payload() == null || event.payload().slotId() == null) {
            log.warn("appointment_cancelled_missing_slot_id eventId={}", event.eventId());
            return;
        }

        log.info("appointment_cancelled_received eventId={} appointmentId={} slotId={}",
                event.eventId(), event.payload().appointmentId(), event.payload().slotId());

        slotStatusUpdateService.markAvailable(event.payload().slotId(), event.payload().appointmentId());
    }

    /**
     * Listens for {@code appointment.expired} events and releases the slot back to AVAILABLE.
     */
    @RabbitListener(queues = "schedule.appointment.expired")
    public void onAppointmentExpired(AppointmentReleasedEvent event) {
        if (event.payload() == null || event.payload().slotId() == null) {
            log.warn("appointment_expired_missing_slot_id eventId={}", event.eventId());
            return;
        }

        log.info("appointment_expired_received eventId={} appointmentId={} slotId={}",
                event.eventId(), event.payload().appointmentId(), event.payload().slotId());

        slotStatusUpdateService.markAvailable(event.payload().slotId(), event.payload().appointmentId());
    }
}
