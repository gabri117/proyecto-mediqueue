package com.mediqueue.appointment.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Outbound DTO representing an appointment returned to the client.
 *
 * @param appointmentId     the appointment's unique identifier
 * @param patientId         the patient's unique identifier
 * @param dentistId         the dentist's unique identifier
 * @param slotId            the time slot's unique identifier
 * @param appointmentDate   the date of the appointment
 * @param startTime         the start time of the appointment
 * @param endTime           the end time of the appointment
 * @param appointmentStatus the current status as a string
 * @param notes             optional free-text notes
 * @param createdAt         the instant the appointment was created
 * @since 0.0.1
 */
public record AppointmentResponse(
        UUID appointmentId,
        UUID patientId,
        UUID dentistId,
        UUID slotId,
        LocalDate appointmentDate,
        LocalTime startTime,
        LocalTime endTime,
        String appointmentStatus,
        String notes,
        Instant createdAt
) {
}
