package com.mediqueue.appointment.client;

import com.mediqueue.appointment.exception.ServiceValidationException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.UUID;

/**
 * HTTP client for validating patient existence against patient-service.
 *
 * <p>Uses Spring Boot 3's {@link RestClient} with a Resilience4j
 * {@link CircuitBreaker} to protect the appointment creation flow
 * from patient-service outages.</p>
 *
 * @since 0.0.2
 */
@Component
public class PatientClient {

    private static final Logger log = LoggerFactory.getLogger(PatientClient.class);
    private static final String CIRCUIT_BREAKER_NAME = "patient-service";

    private final RestClient restClient;

    public PatientClient(
            @Value("${mediqueue.client.patient-service.url:http://localhost:8081}") String baseUrl) {
        this.restClient = RestClient.builder()
                .baseUrl(baseUrl)
                .build();
    }

    /**
     * Validates that a patient exists and is reachable.
     *
     * @param patientId the patient UUID to validate
     * @throws ServiceValidationException if the patient is not found (404),
     *         the service returns an error, or the circuit breaker is open
     */
    @CircuitBreaker(name = CIRCUIT_BREAKER_NAME, fallbackMethod = "validatePatientFallback")
    public void validatePatientExists(UUID patientId) {
        log.debug("Validating patient existence: {}", patientId);

        restClient.get()
                .uri("/patients/{id}", patientId)
                .retrieve()
                .onStatus(HttpStatusCode::is4xxClientError, (request, response) -> {
                    throw new ServiceValidationException("Patient not found or unavailable");
                })
                .onStatus(HttpStatusCode::is5xxServerError, (request, response) -> {
                    throw new ServiceValidationException("Patient not found or unavailable");
                })
                .toBodilessEntity();

        log.debug("Patient validated successfully: {}", patientId);
    }

    /**
     * Fallback invoked when the circuit breaker is open or half-open.
     * The system MUST NOT create appointments with unverified data.
     */
    @SuppressWarnings("unused")
    private void validatePatientFallback(UUID patientId, Throwable t) {
        log.warn("patient_validation_fallback patientId={} reason={}", patientId, t.getMessage());
        throw new ServiceValidationException("Patient not found or unavailable", t);
    }
}
