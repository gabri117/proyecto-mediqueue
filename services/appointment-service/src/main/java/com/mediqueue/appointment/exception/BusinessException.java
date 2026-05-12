package com.mediqueue.appointment.exception;

/**
 * Thrown when a business rule violation occurs (e.g., duplicate request, slot conflict).
 *
 * @since 0.0.1
 */
public class BusinessException extends RuntimeException {

    public BusinessException(String message) {
        super(message);
    }
}
