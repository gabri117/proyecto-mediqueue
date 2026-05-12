package com.mediqueue.payment.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

public record PaymentResponse(
        UUID paymentId,
        UUID appointmentId,
        UUID patientId,
        BigDecimal amount,
        String currency,
        String paymentStatus,
        LocalDateTime requestedAt,
        LocalDateTime resolvedAt) {
}
