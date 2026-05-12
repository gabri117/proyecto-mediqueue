package com.mediqueue.payment.events.published;

import java.time.Instant;
import java.util.UUID;

public record PaymentFailedEvent(
        UUID paymentId,
        UUID appointmentId,
        String reason,
        Instant resolvedAt) {
}
