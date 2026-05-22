package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.PatientClient;
import com.mediqueue.appointment.exception.ServiceValidationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class PatientValidationService {

    private final PatientClient patientClient;
    private final LoadTestDirectValidationService directValidationService;
    private final boolean directDbValidationEnabled;

    public PatientValidationService(PatientClient patientClient,
                                    LoadTestDirectValidationService directValidationService,
                                    @Value("${mediqueue.loadtest.direct-db-validation-enabled:false}") boolean directDbValidationEnabled) {
        this.patientClient = patientClient;
        this.directValidationService = directValidationService;
        this.directDbValidationEnabled = directDbValidationEnabled;
    }

    @Cacheable(value = "patients", key = "#patientId", unless = "#result == false",
            condition = "!@loadTestDirectValidationService.isPreloadEnabled()")
    public boolean validatePatientExists(UUID patientId) {
        if (directDbValidationEnabled) {
            if (!directValidationService.activePatientExists(patientId)) {
                throw new ServiceValidationException("Patient not found or unavailable");
            }
            return true;
        }
        patientClient.validatePatientExists(patientId);
        return true;
    }
}
