package com.mediqueue.appointment.domain.enums;

/**
 * Enumeration representing the publication status of an outbox event.
 */
public enum OutboxPublicationStatus {
    PENDING,
    PUBLISHED,
    FAILED
}
