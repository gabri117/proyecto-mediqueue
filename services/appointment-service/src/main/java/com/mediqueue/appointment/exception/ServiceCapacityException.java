package com.mediqueue.appointment.exception;

/**
 * Raised when a service-local concurrency guard rejects work before it can
 * exhaust database or servlet resources.
 */
public class ServiceCapacityException extends RuntimeException {

    public ServiceCapacityException(String message) {
        super(message);
    }
}
