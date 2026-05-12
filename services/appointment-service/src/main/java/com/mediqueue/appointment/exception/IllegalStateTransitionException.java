package com.mediqueue.appointment.exception;

/**
 * Thrown when an appointment status transition violates the allowed state machine rules.
 *
 * @since 0.0.1
 */
public class IllegalStateTransitionException extends RuntimeException {

    public IllegalStateTransitionException(String message) {
        super(message);
    }
}
