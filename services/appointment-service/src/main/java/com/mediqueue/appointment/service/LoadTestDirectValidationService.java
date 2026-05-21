package com.mediqueue.appointment.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class LoadTestDirectValidationService {

    private static final Logger log = LoggerFactory.getLogger(LoadTestDirectValidationService.class);

    private final JdbcTemplate jdbcTemplate;
    private final boolean preloadEnabled;
    private final AtomicReference<Set<UUID>> activePatientIds = new AtomicReference<>();
    private final AtomicReference<Set<UUID>> availableSlotIds = new AtomicReference<>();
    private final Object patientLoadLock = new Object();
    private final Object slotLoadLock = new Object();

    public LoadTestDirectValidationService(
            JdbcTemplate jdbcTemplate,
            @Value("${mediqueue.loadtest.direct-validation-preload-enabled:false}") boolean preloadEnabled) {
        this.jdbcTemplate = jdbcTemplate;
        this.preloadEnabled = preloadEnabled;
    }

    public boolean activePatientExists(UUID patientId) {
        if (preloadEnabled) {
            return getActivePatientIds().contains(patientId);
        }

        Boolean exists = jdbcTemplate.queryForObject("""
                select exists (
                    select 1
                from patient.patients
                where patient_id = ?
                  and status = 'ACTIVE'::patient.patient_status
                )
                """, Boolean.class, patientId);
        return Boolean.TRUE.equals(exists);
    }

    public boolean availableSlotExists(UUID slotId) {
        if (preloadEnabled) {
            return getAvailableSlotIds().contains(slotId);
        }

        Boolean exists = jdbcTemplate.queryForObject("""
                select exists (
                    select 1
                from schedule.dentist_slots
                where slot_id = ?
                  and display_status = 'AVAILABLE'::schedule.slot_display_status
                )
                """, Boolean.class, slotId);
        return Boolean.TRUE.equals(exists);
    }

    public boolean isPreloadEnabled() {
        return preloadEnabled;
    }

    private Set<UUID> getActivePatientIds() {
        Set<UUID> current = activePatientIds.get();
        if (current != null) {
            return current;
        }
        synchronized (patientLoadLock) {
            current = activePatientIds.get();
            if (current == null) {
                current = loadUuidSet("""
                        select patient_id
                        from patient.patients
                        where status = 'ACTIVE'::patient.patient_status
                        """, "patients");
                activePatientIds.set(current);
            }
            return current;
        }
    }

    private Set<UUID> getAvailableSlotIds() {
        Set<UUID> current = availableSlotIds.get();
        if (current != null) {
            return current;
        }
        synchronized (slotLoadLock) {
            current = availableSlotIds.get();
            if (current == null) {
                current = loadUuidSet("""
                        select slot_id
                        from schedule.dentist_slots
                        where display_status = 'AVAILABLE'::schedule.slot_display_status
                        """, "slots");
                availableSlotIds.set(current);
            }
            return current;
        }
    }

    private Set<UUID> loadUuidSet(String sql, String label) {
        long start = System.nanoTime();
        Set<UUID> ids = new HashSet<>(jdbcTemplate.queryForList(sql, UUID.class));
        long elapsedMs = (System.nanoTime() - start) / 1_000_000;
        log.info("loadtest_direct_validation_preload label={} count={} durationMs={}", label, ids.size(), elapsedMs);
        return Set.copyOf(ids);
    }
}
