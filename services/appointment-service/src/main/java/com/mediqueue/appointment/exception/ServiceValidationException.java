package com.mediqueue.appointment.exception;

/**
 * Thrown when an external service validation fails (e.g., patient or slot
 * does not exist, or the upstream service is unavailable).
 *
 * <p>Mapped to HTTP 422 Unprocessable Entity by {@link GlobalExceptionHandler}.</p>
 *
 * @since 0.0.2
 */
public class ServiceValidationException extends RuntimeException {

    public ServiceValidationException(String message) {
        super(message);
    }

    public ServiceValidationException(String message, Throwable cause) {
        super(message, cause);
    }
}
