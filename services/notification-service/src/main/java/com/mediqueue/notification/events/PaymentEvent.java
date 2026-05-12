package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class PaymentEvent {

    private UUID paymentId;
    private UUID appointmentId;
    private UUID patientId;
    private String eventType;         // PAYMENT_SUCCEEDED, PAYMENT_FAILED
    private String paymentStatus;
    private BigDecimal amount;
    private String currency;
    private String patientEmail;
    private String patientPhone;
    private String failureReason;
    private LocalDateTime occurredAt;
}
