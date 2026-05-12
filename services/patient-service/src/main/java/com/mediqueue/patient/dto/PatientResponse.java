package com.mediqueue.patient.dto;

import com.mediqueue.patient.domain.enums.PatientStatus;
import java.time.LocalDateTime;
import java.util.UUID;

public record PatientResponse(
        UUID patientId,
        String firstName,
        String lastName,
        String email,
        String phone,
        String documentNumber,
        PatientStatus status,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
}
