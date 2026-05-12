package com.mediqueue.appointment.events.published;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Event emitted when an appointment expires due to hold TTL timeout.
 *
 * @param eventId    unique event identifier
 * @param eventType  always {@code "APPOINTMENT_EXPIRED"}
 * @param occurredAt ISO 8601 UTC timestamp of when the event occurred
 * @param payload    event-specific data
 * @since 0.0.1
 */
public record AppointmentExpiredEvent(
        String eventId,
        String eventType,
        String occurredAt,
        AppointmentExpiredPayload payload
) {

    /**
     * Payload carrying the details of the expired appointment.
     *
     * @param appointmentId   the appointment's unique identifier
     * @param patientId       the patient's unique identifier
     * @param dentistId       the dentist's unique identifier
     * @param appointmentDate the date of the appointment
     * @param startTime       the start time of the appointment
     */
    public record AppointmentExpiredPayload(
            UUID appointmentId,
            UUID patientId,
            UUID dentistId,
            LocalDate appointmentDate,
            LocalTime startTime
    ) {
    }
}
