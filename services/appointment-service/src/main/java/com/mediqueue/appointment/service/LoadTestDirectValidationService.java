package com.mediqueue.appointment.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class LoadTestDirectValidationService {

    private final JdbcTemplate jdbcTemplate;

    public LoadTestDirectValidationService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public boolean activePatientExists(UUID patientId) {
        Boolean exists = jdbcTemplate.queryForObject("""
                select exists (
                    select 1
                    from patient.patients
                    where patient_id = ?
                      and status::text = 'ACTIVE'
                )
                """, Boolean.class, patientId);
        return Boolean.TRUE.equals(exists);
    }

    public boolean availableSlotExists(UUID slotId) {
        Boolean exists = jdbcTemplate.queryForObject("""
                select exists (
                    select 1
                    from schedule.dentist_slots
                    where slot_id = ?
                      and display_status::text = 'AVAILABLE'
                )
                """, Boolean.class, slotId);
        return Boolean.TRUE.equals(exists);
    }
}
