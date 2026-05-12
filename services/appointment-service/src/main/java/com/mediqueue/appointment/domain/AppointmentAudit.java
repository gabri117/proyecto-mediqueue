package com.mediqueue.appointment.domain;

import com.mediqueue.appointment.domain.enums.AppointmentStatus;
import jakarta.persistence.Column;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapped to the {@code appointment_audit} table.
 *
 * <p>Immutable audit trail for appointment status transitions.
 * The database enforces immutability via triggers that block
 * {@code UPDATE} and {@code DELETE} operations on this table.</p>
 *
 * @since 0.0.1
 */
@Entity
@Table(name = "appointment_audit")
@Getter
@Setter
@NoArgsConstructor
public class AppointmentAudit {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "audit_id", updatable = false, nullable = false)
    private UUID auditId;

    @Column(name = "appointment_id", nullable = false)
    private UUID appointmentId;

    @Enumerated(EnumType.STRING)
    @Column(name = "previous_status")
    private AppointmentStatus previousStatus;
 
    @Enumerated(EnumType.STRING)
    @Column(name = "new_status", nullable = false)
    private AppointmentStatus newStatus;

    @Column(name = "change_reason", length = 200)
    private String changeReason;

    @CreationTimestamp
    @Column(name = "changed_at", nullable = false, updatable = false)
    private Instant changedAt;
}
