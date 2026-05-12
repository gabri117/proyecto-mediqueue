package com.mediqueue.schedule.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record DentistRequest(
        @NotBlank
        String firstName,
        @NotBlank
        String lastName,
        @NotBlank
        String specialty,
        @NotBlank
        @Email
        String email,
        @NotBlank
        String licenseNumber
) {
}
