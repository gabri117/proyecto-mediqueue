package com.mediqueue.notification.domain;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "notifications")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Notification {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "notification_id")
    private UUID notificationId;

    @Column(name = "patient_id", nullable = false)
    private UUID patientId;

    @Column(name = "appointment_id")
    private UUID appointmentId;

    @Column(name = "event_type", nullable = false, length = 80)
    private String eventType;

    @Column(name = "source_event_id")
    private UUID sourceEventId;

    @Column(name = "source_event_type", length = 100)
    private String sourceEventType;

    @Column(name = "source_service", length = 80)
    private String sourceService;

    @Column(name = "event_key", length = 255)
    private String eventKey;

    @Column(name = "routing_key", length = 120)
    private String routingKey;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "channel", nullable = false,
            columnDefinition = "notification_channel")
    @Builder.Default
    private NotificationChannel channel = NotificationChannel.EMAIL;

    @Column(name = "destination", nullable = false, length = 200)
    private String destination;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "notification_status", nullable = false,
            columnDefinition = "notification_status")
    @Builder.Default
    private NotificationStatus notificationStatus = NotificationStatus.PENDING;

    @Column(name = "error_message", length = 255)
    private String errorMessage;

    @Column(name = "attempt_count", nullable = false)
    @Builder.Default
    private Integer attemptCount = 0;

    @Column(name = "created_at", nullable = false, updatable = false)
    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "sent_at")
    private LocalDateTime sentAt;
}
