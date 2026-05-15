package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class AppointmentEvent {

    private String eventId;
    private UUID appointmentId;
    private UUID patientId;
    private UUID dentistId;
    private UUID slotId;
    private String eventType;         // APPOINTMENT_HELD, APPOINTMENT_CONFIRMED, APPOINTMENT_CANCELLED, APPOINTMENT_EXPIRED
    private String appointmentStatus;
    private String patientEmail;
    private String patientPhone;
    private String doctorName;
    private String specialty;
    private String slotDate;
    private BigDecimal amount;
    private String reason;
    private String occurredAt;
    private Payload payload;

    public UUID effectiveAppointmentId() {
        return appointmentId != null ? appointmentId : payload != null ? payload.getAppointmentId() : null;
    }

    public UUID effectivePatientId() {
        return patientId != null ? patientId : payload != null ? payload.getPatientId() : null;
    }

    public String effectiveEventType() {
        return eventType;
    }

    public BigDecimal effectiveAmount() {
        return amount != null ? amount : payload != null ? payload.getAmount() : null;
    }

    @Data
    @NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Payload {
        private UUID appointmentId;
        private UUID patientId;
        private UUID dentistId;
        private UUID slotId;
        private LocalDate appointmentDate;
        private LocalTime startTime;
        private LocalTime endTime;
        private BigDecimal amount;
    }
}
