package com.mediqueue.schedule.dto;

import java.time.LocalDateTime;
import java.util.UUID;

public record DentistResponse(
        UUID dentistId,
        String firstName,
        String lastName,
        String specialty,
        String email,
        String licenseNumber,
        String status,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
}
