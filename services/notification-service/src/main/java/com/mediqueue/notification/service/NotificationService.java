package com.mediqueue.notification.service;

import com.mediqueue.notification.domain.Notification;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.domain.NotificationStatus;
import com.mediqueue.notification.dto.NotificationResponse;
import com.mediqueue.notification.repository.NotificationRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.persistence.criteria.Predicate;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
public class NotificationService {

    private final NotificationRepository notificationRepository;
    private final Counter eventsConsumedCounter;
    private final Counter sentCounter;
    private final Counter failedCounter;
    private final Counter duplicateCounter;

    public NotificationService(NotificationRepository notificationRepository, MeterRegistry meterRegistry) {
        this.notificationRepository = notificationRepository;
        this.eventsConsumedCounter = meterRegistry.counter("notification.events.consumed.total");
        this.sentCounter = meterRegistry.counter("notifications.sent.total");
        this.failedCounter = meterRegistry.counter("notifications.failed.total");
        this.duplicateCounter = meterRegistry.counter("notifications.duplicate.total");
    }

    public NotificationProcessingResult processAndSend(
            UUID patientId,
            UUID appointmentId,
            UUID paymentId,
            String sourceEventId,
            String eventType,
            String sourceService,
            String routingKey,
            String destination,
            NotificationChannel channel
    ) {
        if (patientId == null) {
            throw new NonRetryableNotificationException("patientId is required to create notification");
        }
        if (!StringUtils.hasText(eventType)) {
            throw new NonRetryableNotificationException("eventType is required to create notification");
        }
        if (!StringUtils.hasText(destination)) {
            throw new NonRetryableNotificationException("destination is required to create notification");
        }

        String eventKey = buildEventKey(sourceEventId, eventType, appointmentId, paymentId, patientId, channel);
        if (notificationRepository.existsByEventKey(eventKey)) {
            duplicateCounter.increment();
            log.info("notification_duplicate eventType={} eventKey={} patientId={} appointmentId={} paymentId={} routingKey={}",
                    eventType, eventKey, patientId, appointmentId, paymentId, routingKey);
            return NotificationProcessingResult.DUPLICATE;
        }

        eventsConsumedCounter.increment();
        Notification notification = Notification.builder()
                .patientId(patientId)
                .appointmentId(appointmentId)
                .eventType(eventType)
                .sourceEventId(parseUuid(sourceEventId))
                .sourceEventType(eventType)
                .sourceService(sourceService)
                .eventKey(eventKey)
                .routingKey(routingKey)
                .destination(destination)
                .channel(channel)
                .notificationStatus(NotificationStatus.PENDING)
                .attemptCount(1)
                .build();

        try {
            notificationRepository.saveAndFlush(notification);
            simulateSend(notification);
            notification.setNotificationStatus(NotificationStatus.SENT);
            notification.setSentAt(LocalDateTime.now());
            sentCounter.increment();
            log.info("notification_sent eventType={} eventKey={} patientId={} appointmentId={} paymentId={} notificationStatus={} id={}",
                    eventType, eventKey, patientId, appointmentId, paymentId,
                    notification.getNotificationStatus(), notification.getNotificationId());
        } catch (DataIntegrityViolationException ex) {
            duplicateCounter.increment();
            log.info("notification_duplicate_race eventType={} eventKey={} patientId={} appointmentId={} paymentId={}",
                    eventType, eventKey, patientId, appointmentId, paymentId);
            return NotificationProcessingResult.DUPLICATE;
        } catch (Exception ex) {
            notification.setNotificationStatus(NotificationStatus.FAILED);
            notification.setErrorMessage(truncate(ex.getMessage(), 255));
            failedCounter.increment();
            log.error("notification_failed eventType={} eventKey={} patientId={} appointmentId={} paymentId={} notificationStatus={} error={}",
                    eventType, eventKey, patientId, appointmentId, paymentId,
                    notification.getNotificationStatus(), ex.getMessage());
        }

        notificationRepository.save(notification);
        return notification.getNotificationStatus() == NotificationStatus.SENT
                ? NotificationProcessingResult.CREATED_SENT
                : NotificationProcessingResult.CREATED_FAILED;
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> findAll(Pageable pageable) {
        return notificationRepository.findAll(pageable)
                .map(NotificationResponse::from);
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> search(
            UUID patientId,
            UUID appointmentId,
            NotificationStatus status,
            Pageable pageable
    ) {
        Specification<Notification> specification = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();
            if (patientId != null) {
                predicates.add(cb.equal(root.get("patientId"), patientId));
            }
            if (appointmentId != null) {
                predicates.add(cb.equal(root.get("appointmentId"), appointmentId));
            }
            if (status != null) {
                predicates.add(cb.equal(root.get("notificationStatus"), status));
            }
            return cb.and(predicates.toArray(Predicate[]::new));
        };
        return notificationRepository.findAll(specification, pageable)
                .map(NotificationResponse::from);
    }

    @Transactional(readOnly = true)
    public NotificationResponse findById(UUID id) {
        return notificationRepository.findById(id)
                .map(NotificationResponse::from)
                .orElseThrow(() -> new NotificationNotFoundException(id));
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> findByPatientId(UUID patientId, Pageable pageable) {
        return notificationRepository.findByPatientId(patientId, pageable)
                .map(NotificationResponse::from);
    }

    protected void simulateSend(Notification notification) {
        log.debug("Simulating {} notification to {} for event {}",
                notification.getChannel(), notification.getDestination(), notification.getEventType());
    }

    public String buildEventKey(String sourceEventId,
                                String eventType,
                                UUID appointmentId,
                                UUID paymentId,
                                UUID patientId,
                                NotificationChannel channel) {
        if (StringUtils.hasText(sourceEventId)) {
            return sourceEventId.trim();
        }
        String rawKey = String.join(":",
                nullSafe(eventType),
                nullSafe(appointmentId),
                nullSafe(paymentId),
                nullSafe(patientId),
                nullSafe(channel));
        return UUID.nameUUIDFromBytes(rawKey.getBytes(StandardCharsets.UTF_8)).toString();
    }

    private UUID parseUuid(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        try {
            return UUID.fromString(value.trim());
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private String nullSafe(Object value) {
        return value == null ? "null" : value.toString();
    }

    private String truncate(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    public static class NotificationNotFoundException extends RuntimeException {
        public NotificationNotFoundException(UUID id) {
            super("Notification not found: " + id);
        }
    }
}
