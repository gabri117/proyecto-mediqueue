package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class PaymentEvent {

    private String eventId;
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
    private String occurredAt;
    private Payload payload;

    public UUID effectivePaymentId() {
        return paymentId != null ? paymentId : payload != null ? payload.getPaymentId() : null;
    }

    public UUID effectiveAppointmentId() {
        return appointmentId != null ? appointmentId : payload != null ? payload.getAppointmentId() : null;
    }

    public UUID effectivePatientId() {
        return patientId != null ? patientId : payload != null ? payload.getPatientId() : null;
    }

    public BigDecimal effectiveAmount() {
        return amount != null ? amount : payload != null ? payload.getAmount() : null;
    }

    public String effectiveFailureReason() {
        return failureReason != null ? failureReason : payload != null ? payload.getReason() : null;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Payload {
        private UUID paymentId;
        private UUID appointmentId;
        private UUID patientId;
        private BigDecimal amount;
        private String currency;
        private String reason;
    }
}
