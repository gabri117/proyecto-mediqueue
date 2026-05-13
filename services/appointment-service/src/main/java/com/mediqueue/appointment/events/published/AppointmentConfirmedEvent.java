package com.mediqueue.appointment.events.published;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Event emitted when an appointment is confirmed after successful payment.
 *
 * @param eventId    unique event identifier
 * @param eventType  always {@code "APPOINTMENT_CONFIRMED"}
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record AppointmentConfirmedEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentConfirmedPayload payload
) {

    /**
     * Payload carrying the details of the confirmed appointment.
     *
     * @param appointmentId   the appointment's unique identifier
     * @param patientId       the patient's unique identifier
     * @param dentistId       the dentist's unique identifier
     * @param slotId          the reserved time slot
     * @param appointmentDate the date of the appointment
     * @param startTime       the start time of the appointment
     */
    public record AppointmentConfirmedPayload(
            UUID appointmentId,
            UUID patientId,
            UUID dentistId,
            UUID slotId,
            LocalDate appointmentDate,
            LocalTime startTime
    ) {
    }
}
