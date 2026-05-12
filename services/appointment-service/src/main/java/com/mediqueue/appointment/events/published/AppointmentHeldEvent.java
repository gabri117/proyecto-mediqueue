package com.mediqueue.appointment.events.published;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Event emitted when an appointment is held (reserved with a TTL pending payment).
 *
 * @param eventId    unique event identifier
 * @param eventType  always {@code "APPOINTMENT_HELD"}
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record AppointmentHeldEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentHeldPayload payload
) {

    /**
     * Payload carrying the details of the held appointment.
     *
     * @param appointmentId   the appointment's unique identifier
     * @param patientId       the patient's unique identifier
     * @param dentistId       the dentist's unique identifier
     * @param slotId          the reserved time slot
     * @param appointmentDate the date of the appointment
     * @param startTime       the start time of the appointment
     * @param endTime         the end time of the appointment
     * @param holdExpiresAt   the instant when the hold expires
     * @param amount          the expected payment amount (nullable)
     */
    public record AppointmentHeldPayload(
            UUID appointmentId,
            UUID patientId,
            UUID dentistId,
            UUID slotId,
            LocalDate appointmentDate,
            LocalTime startTime,
            LocalTime endTime,
            Instant holdExpiresAt,
            BigDecimal amount
    ) {
    }
}
