package com.mediqueue.schedule.messaging.events;

import java.util.UUID;

/**
 * Inbound event contract matching payloads published by appointment-service
 * with routing keys {@code appointment.cancelled} or {@code appointment.expired}.
 *
 * <p>Both routing keys share the same payload structure; a single DTO handles both.</p>
 *
 * @since 0.0.2
 */
public record AppointmentReleasedEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentReleasedPayload payload
) {

    public record AppointmentReleasedPayload(
            UUID appointmentId,
            UUID slotId
    ) {
    }
}
