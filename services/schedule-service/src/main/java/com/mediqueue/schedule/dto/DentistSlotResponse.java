package com.mediqueue.schedule.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.UUID;

public record DentistSlotResponse(
        UUID slotId,
        UUID dentistId,
        LocalDate slotDate,
        LocalTime startTime,
        LocalTime endTime,
        String status,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
}
