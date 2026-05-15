package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class PaymentEventPayload {

    private UUID paymentId;
    private UUID appointmentId;
    private UUID patientId;
    private BigDecimal amount;
    private String currency;
    private String paymentStatus;
    private String failureReason;
    private String reason;
    private String patientEmail;
    private String patientPhone;
    private Instant resolvedAt;

    public String effectiveFailureReason() {
        return failureReason != null ? failureReason : reason;
    }
}
