package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.AppointmentAudit;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

/**
 * Spring Data JPA repository for {@link AppointmentAudit} entities.
 *
 * <p>This table is append-only. The database enforces immutability
 * via triggers that block {@code UPDATE} and {@code DELETE}.</p>
 *
 * @since 0.0.1
 */
public interface AppointmentAuditRepository extends JpaRepository<AppointmentAudit, UUID> {
}
