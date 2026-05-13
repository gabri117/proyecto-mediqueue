package com.mediqueue.schedule.messaging.events;

import java.util.UUID;

/**
 * Inbound event contract matching the payload published by appointment-service
 * with routing key {@code appointment.held}.
 *
 * <p>Only the fields needed for slot state management are mapped here;
 * unknown fields in the JSON are silently ignored by Jackson.</p>
 *
 * @since 0.0.2
 */
public record AppointmentHeldEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentHeldPayload payload
) {

    public record AppointmentHeldPayload(
            UUID appointmentId,
            UUID slotId
    ) {
    }
}
