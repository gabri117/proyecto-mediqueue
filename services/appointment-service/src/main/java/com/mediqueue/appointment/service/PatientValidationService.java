package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.PatientClient;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class PatientValidationService {

    private final PatientClient patientClient;

    public PatientValidationService(PatientClient patientClient) {
        this.patientClient = patientClient;
    }

    @Cacheable(value = "patients", key = "#patientId", unless = "#result == false")
    public boolean validatePatientExists(UUID patientId) {
        patientClient.validatePatientExists(patientId);
        return true;
    }
}
