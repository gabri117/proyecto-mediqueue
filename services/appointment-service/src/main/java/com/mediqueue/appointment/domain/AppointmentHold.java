package com.mediqueue.appointment.domain;

import com.mediqueue.appointment.domain.enums.HoldStatus;
import jakarta.persistence.Column;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapped to the {@code appointment_holds} table.
 *
 * <p>Represents a temporary reservation on a time slot with a TTL.
 * Protects against zombie holds caused by stalled payment flows.
 * Only one {@code ACTIVE} hold per slot is enforced at the database level.</p>
 *
 * @since 0.0.1
 */
@Entity
@Table(name = "appointment_holds")
@Getter
@Setter
@NoArgsConstructor
public class AppointmentHold {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "hold_id", updatable = false, nullable = false)
    private UUID holdId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "appointment_id", nullable = false)
    private Appointment appointment;

    @Column(name = "slot_id", nullable = false)
    private UUID slotId;

    @Enumerated(EnumType.STRING)
    @Column(name = "hold_status", nullable = false)
    private HoldStatus holdStatus = HoldStatus.ACTIVE;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "released_at")
    private Instant releasedAt;
}
