package com.mediqueue.notification.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class EventEnvelope<T> {

    private UUID eventId;
    private String eventType;
    private Instant occurredAt;
    private T payload;
}
