package com.mediqueue.appointment.dto;

import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * Inbound DTO for creating a new appointment.
 *
 * @param patientId       the patient's unique identifier
 * @param dentistId       the dentist's unique identifier
 * @param slotId          the time slot's unique identifier
 * @param appointmentDate the date of the appointment
 * @param startTime       the start time of the appointment
 * @param endTime         the end time of the appointment
 * @param notes           optional free-text notes
 * @since 0.0.1
 */
public record AppointmentRequest(
        @NotNull UUID patientId,
        @NotNull UUID dentistId,
        @NotNull UUID slotId,
        @NotNull LocalDate appointmentDate,
        @NotNull LocalTime startTime,
        @NotNull LocalTime endTime,
        String notes
) {
}
