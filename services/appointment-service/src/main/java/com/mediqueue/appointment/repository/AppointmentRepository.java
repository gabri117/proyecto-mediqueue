package com.mediqueue.appointment.repository;

import com.mediqueue.appointment.domain.Appointment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

/**
 * Spring Data JPA repository for {@link Appointment} entities.
 *
 * @since 0.0.1
 */
public interface AppointmentRepository extends JpaRepository<Appointment, UUID> {

    /**
     * Finds all appointments belonging to a given patient.
     *
     * @param patientId the patient's unique identifier
     * @return list of appointments for the patient
     */
    List<Appointment> findByPatientId(UUID patientId);
}
