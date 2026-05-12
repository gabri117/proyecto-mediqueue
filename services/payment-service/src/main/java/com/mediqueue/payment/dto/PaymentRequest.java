package com.mediqueue.payment.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.UUID;

public record PaymentRequest(
        @NotNull UUID appointmentId,
        @NotNull UUID patientId,
        @NotNull @DecimalMin("0.01") BigDecimal amount,
        String currency) {

    public String normalizedCurrency() {
        return currency == null || currency.isBlank() ? "GTQ" : currency.trim().toUpperCase();
    }
}
