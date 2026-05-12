package com.mediqueue.payment.events.published;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public record PaymentSucceededEvent(
        UUID paymentId,
        UUID appointmentId,
        UUID patientId,
        BigDecimal amount,
        Instant resolvedAt) {
}
