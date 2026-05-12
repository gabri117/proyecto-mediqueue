package com.mediqueue.appointment.events.consumed;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * Inbound event consumed from the payment service when a payment succeeds.
 *
 * @param eventId    unique event identifier
 * @param eventType  the event type as published by the payment service
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record PaymentSucceededEvent(
        String eventId,
        String eventType,
        String occurredAt,
        PaymentSucceededPayload payload
) {

    /**
     * Payload carrying the details of the successful payment.
     *
     * @param paymentId     the payment's unique identifier
     * @param appointmentId the associated appointment
     * @param patientId     the patient who paid
     * @param amount        the amount paid
     * @param resolvedAt    the instant the payment was resolved
     */
    public record PaymentSucceededPayload(
            UUID paymentId,
            UUID appointmentId,
            UUID patientId,
            BigDecimal amount,
            Instant resolvedAt
    ) {
    }
}
