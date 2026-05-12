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
        NotificationChannel channel,
        String destination,
        NotificationStatus notificationStatus,
        String errorMessage,
        LocalDateTime createdAt,
        LocalDateTime sentAt
) {
    public static NotificationResponse from(Notification n) {
        return NotificationResponse.builder()
                .notificationId(n.getNotificationId())
                .patientId(n.getPatientId())
                .appointmentId(n.getAppointmentId())
                .eventType(n.getEventType())
                .channel(n.getChannel())
                .destination(n.getDestination())
                .notificationStatus(n.getNotificationStatus())
                .errorMessage(n.getErrorMessage())
                .createdAt(n.getCreatedAt())
                .sentAt(n.getSentAt())
                .build();
    }
}
