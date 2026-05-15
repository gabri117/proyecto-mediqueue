package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class AppointmentEventPayload {

    private UUID appointmentId;
    private UUID patientId;
    private UUID slotId;
    private String appointmentStatus;
    private String patientEmail;
    private String patientPhone;
    private String doctorName;
    private String specialty;
    private LocalDate slotDate;
    private LocalDate appointmentDate;
    private BigDecimal amount;
    private String reason;

    public LocalDate effectiveSlotDate() {
        return slotDate != null ? slotDate : appointmentDate;
    }
}
