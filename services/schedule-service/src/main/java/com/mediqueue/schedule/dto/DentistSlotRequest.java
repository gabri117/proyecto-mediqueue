package com.mediqueue.schedule.dto;

import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

public record DentistSlotRequest(
        @NotNull
        UUID dentistId,
        @NotNull
        LocalDate slotDate,
        @NotNull
        LocalTime startTime,
        @NotNull
        LocalTime endTime
) {
}
