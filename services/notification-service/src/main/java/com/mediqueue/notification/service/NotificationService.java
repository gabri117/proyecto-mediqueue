package com.mediqueue.notification.service;

import com.mediqueue.notification.domain.Notification;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.domain.NotificationStatus;
import com.mediqueue.notification.dto.NotificationResponse;
import com.mediqueue.notification.repository.NotificationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationService {

    private final NotificationRepository notificationRepository;

    @Transactional
    public void processAndSend(
            UUID patientId,
            UUID appointmentId,
            String eventType,
            String destination,
            NotificationChannel channel
    ) {
        Notification notification = Notification.builder()
                .patientId(patientId)
                .appointmentId(appointmentId)
                .eventType(eventType)
                .destination(destination)
                .channel(channel)
                .notificationStatus(NotificationStatus.PENDING)
                .build();

        notificationRepository.save(notification);

        try {
            simulateSend(notification);
            notification.setNotificationStatus(NotificationStatus.SENT);
            notification.setSentAt(LocalDateTime.now());
            log.info("Notificación enviada: tipo={} destino={} id={}",
                    eventType, destination, notification.getNotificationId());
        } catch (Exception ex) {
            notification.setNotificationStatus(NotificationStatus.FAILED);
            notification.setErrorMessage(truncate(ex.getMessage(), 255));
            log.error("Fallo al enviar notificación: tipo={} destino={} error={}",
                    eventType, destination, ex.getMessage());
        }

        notificationRepository.save(notification);
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> findAll(Pageable pageable) {
        return notificationRepository.findAll(pageable)
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

    private void simulateSend(Notification notification) {
        // Simulación de envío: solo log. En producción llamaría al proveedor real.
        log.debug("Simulando envío {} a {} para evento {}",
                notification.getChannel(), notification.getDestination(), notification.getEventType());
    }

    private String truncate(String value, int maxLength) {
        if (value == null) return null;
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    public static class NotificationNotFoundException extends RuntimeException {
        public NotificationNotFoundException(UUID id) {
            super("Notificación no encontrada: " + id);
        }
    }
}
