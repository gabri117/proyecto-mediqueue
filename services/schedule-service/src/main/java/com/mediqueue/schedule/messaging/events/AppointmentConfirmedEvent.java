package com.mediqueue.schedule.messaging.events;

import java.util.UUID;

/**
 * Inbound event contract matching the payload published by appointment-service
 * with routing key {@code appointment.confirmed}.
 *
 * @since 0.0.2
 */
public record AppointmentConfirmedEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentConfirmedPayload payload
) {

    public record AppointmentConfirmedPayload(
            UUID appointmentId,
            UUID slotId
    ) {
    }
}
