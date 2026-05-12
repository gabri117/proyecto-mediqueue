package com.mediqueue.appointment.domain.enums;

/**
 * Enumeration representing the processing status of an idempotent request.
 */
public enum IdempotencyStatus {
    PROCESSING,
    SUCCEEDED,
    FAILED
}
