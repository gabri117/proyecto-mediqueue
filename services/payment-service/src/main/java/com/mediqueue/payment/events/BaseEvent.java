package com.mediqueue.payment.events;

import java.time.Instant;
import java.util.UUID;

public record BaseEvent<T>(
        UUID eventId,
        String eventType,
        Instant occurredAt,
        T payload) {

    public static <T> BaseEvent<T> of(String eventType, T payload) {
        return new BaseEvent<>(UUID.randomUUID(), eventType, Instant.now(), payload);
    }
}
