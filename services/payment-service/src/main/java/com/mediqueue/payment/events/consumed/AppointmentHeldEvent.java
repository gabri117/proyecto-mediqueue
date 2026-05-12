package com.mediqueue.payment.events.consumed;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

public record AppointmentHeldEvent(
        UUID eventId,
        String eventType,
        Instant occurredAt,
        Payload payload) {

    public record Payload(
            UUID appointmentId,
            UUID patientId,
            UUID dentistId,
            UUID slotId,
            LocalDate appointmentDate,
            LocalTime startTime,
            LocalTime endTime,
            Instant holdExpiresAt,
            BigDecimal amount) {
    }
}
