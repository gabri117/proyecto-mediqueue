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
 * HTTP client for validating slot existence against schedule-service.
 *
 * <p>Uses Spring Boot 3's {@link RestClient} with a Resilience4j
 * {@link CircuitBreaker} to protect the appointment creation flow
 * from schedule-service outages.</p>
 *
 * @since 0.0.2
 */
@Component
public class ScheduleClient {

    private static final Logger log = LoggerFactory.getLogger(ScheduleClient.class);
    private static final String CIRCUIT_BREAKER_NAME = "schedule-service";

    private final RestClient restClient;

    public ScheduleClient(
            @Value("${mediqueue.client.schedule-service.url:http://localhost:8082}") String baseUrl) {
        this.restClient = RestClient.builder()
                .baseUrl(baseUrl)
                .build();
    }

    /**
     * Validates that a slot exists and is reachable.
     *
     * @param slotId the slot UUID to validate
     * @throws ServiceValidationException if the slot is not found (404),
     *         the service returns an error, or the circuit breaker is open
     */
    @CircuitBreaker(name = CIRCUIT_BREAKER_NAME, fallbackMethod = "validateSlotFallback")
    public void validateSlotExists(UUID slotId) {
        log.debug("Validating slot existence: {}", slotId);

        restClient.get()
                .uri("/slots/{id}", slotId)
                .retrieve()
                .onStatus(HttpStatusCode::is4xxClientError, (request, response) -> {
                    throw new ServiceValidationException("Slot not found or unavailable");
                })
                .onStatus(HttpStatusCode::is5xxServerError, (request, response) -> {
                    throw new ServiceValidationException("Slot not found or unavailable");
                })
                .toBodilessEntity();

        log.debug("Slot validated successfully: {}", slotId);
    }

    /**
     * Fallback invoked when the circuit breaker is open or half-open.
     * The system MUST NOT create appointments with unverified data.
     */
    @SuppressWarnings("unused")
    private void validateSlotFallback(UUID slotId, Throwable t) {
        log.warn("slot_validation_fallback slotId={} reason={}", slotId, t.getMessage());
        throw new ServiceValidationException("Slot not found or unavailable", t);
    }
}
