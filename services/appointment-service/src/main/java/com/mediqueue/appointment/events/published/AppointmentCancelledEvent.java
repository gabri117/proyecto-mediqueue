package com.mediqueue.appointment.events.published;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Event emitted when an appointment is cancelled.
 *
 * @param eventId    unique event identifier
 * @param eventType  always {@code "APPOINTMENT_CANCELLED"}
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record AppointmentCancelledEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentCancelledPayload payload
) {

    /**
     * Payload carrying the details of the cancelled appointment.
     *
     * @param appointmentId   the appointment's unique identifier
     * @param patientId       the patient's unique identifier
     * @param dentistId       the dentist's unique identifier
     * @param appointmentDate the date of the appointment
     * @param startTime       the start time of the appointment
     */
    public record AppointmentCancelledPayload(
            UUID appointmentId,
            UUID patientId,
            UUID dentistId,
            LocalDate appointmentDate,
            LocalTime startTime
    ) {
    }
}
