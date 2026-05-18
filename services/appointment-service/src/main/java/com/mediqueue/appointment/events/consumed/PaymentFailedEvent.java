package com.mediqueue.appointment.events.consumed;

import java.time.Instant;
import java.util.UUID;

/**
 * Inbound event consumed from the payment service when a payment fails.
 *
 * @param eventId    unique event identifier
 * @param eventType  the event type as published by the payment service
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record PaymentFailedEvent(
        String eventId,
        String eventType,
        String occurredAt,
        PaymentFailedPayload payload
) {

    /**
     * Payload carrying the details of the failed payment.
     *
     * @param paymentId     the payment's unique identifier
     * @param appointmentId the associated appointment
     * @param patientId     the patient who owns the appointment
     * @param reason        human-readable failure reason
     * @param resolvedAt    the instant the payment was resolved
     */
    public record PaymentFailedPayload(
            UUID paymentId,
            UUID appointmentId,
            UUID patientId,
            String reason,
            Instant resolvedAt
    ) {
    }
}
