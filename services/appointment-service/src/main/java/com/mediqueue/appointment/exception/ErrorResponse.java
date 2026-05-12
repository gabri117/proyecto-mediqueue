package com.mediqueue.appointment.exception;

import java.time.Instant;

/**
 * Standard error response body returned by all exception handlers.
 *
 * @param code      machine-readable error code
 * @param message   human-readable error description
 * @param timestamp the instant the error occurred
 * @since 0.0.1
 */
public record ErrorResponse(
        String code,
        String message,
        Instant timestamp
) {
}
