package com.mediqueue.notification.dto;

import com.mediqueue.notification.domain.Notification;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.domain.NotificationStatus;
import lombok.Builder;

import java.time.LocalDateTime;
import java.util.UUID;

@Builder
public record NotificationResponse(
        UUID notificationId,
        UUID patientId,
        UUID appointmentId,
        String eventType,
        UUID sourceEventId,
        String sourceEventType,
        String sourceService,
        String eventKey,
        String routingKey,
        NotificationChannel channel,
        String destination,
        NotificationStatus notificationStatus,
        String errorMessage,
        Integer attemptCount,
        LocalDateTime createdAt,
        LocalDateTime sentAt
) {
    public static NotificationResponse from(Notification n) {
        return NotificationResponse.builder()
                .notificationId(n.getNotificationId())
                .patientId(n.getPatientId())
                .appointmentId(n.getAppointmentId())
                .eventType(n.getEventType())
                .sourceEventId(n.getSourceEventId())
                .sourceEventType(n.getSourceEventType())
                .sourceService(n.getSourceService())
                .eventKey(n.getEventKey())
                .routingKey(n.getRoutingKey())
                .channel(n.getChannel())
                .destination(n.getDestination())
                .notificationStatus(n.getNotificationStatus())
                .errorMessage(n.getErrorMessage())
                .attemptCount(n.getAttemptCount())
                .createdAt(n.getCreatedAt())
                .sentAt(n.getSentAt())
                .build();
    }
}
