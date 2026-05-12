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
public class AppointmentEvent {

    private UUID appointmentId;
    private UUID patientId;
    private UUID slotId;
    private String eventType;         // APPOINTMENT_HELD, APPOINTMENT_CONFIRMED, APPOINTMENT_CANCELLED, APPOINTMENT_EXPIRED
    private String appointmentStatus;
    private String patientEmail;
    private String patientPhone;
    private String doctorName;
    private String specialty;
    private LocalDateTime slotDate;
    private BigDecimal amount;
    private String reason;
    private LocalDateTime occurredAt;
}
