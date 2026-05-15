package com.mediqueue.notification.service;

import com.mediqueue.notification.domain.Notification;
import com.mediqueue.notification.domain.NotificationChannel;
import com.mediqueue.notification.domain.NotificationStatus;
import com.mediqueue.notification.repository.NotificationRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NotificationServiceTest {

    private final NotificationRepository repository = mock(NotificationRepository.class);

    @Test
    void validEventCreatesSentNotification() {
        NotificationService service = new NotificationService(repository, new SimpleMeterRegistry());
        when(repository.existsByEventKey("event-1")).thenReturn(false);
        when(repository.saveAndFlush(any(Notification.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(repository.save(any(Notification.class))).thenAnswer(invocation -> invocation.getArgument(0));

        NotificationProcessingResult result = service.processAndSend(
                UUID.randomUUID(),
                UUID.randomUUID(),
                null,
                "event-1",
                "APPOINTMENT_CONFIRMED",
                "appointment-service",
                "appointment.confirmed",
                "patient@mediqueue.test",
                NotificationChannel.EMAIL);

        assertThat(result).isEqualTo(NotificationProcessingResult.CREATED_SENT);
        verify(repository).saveAndFlush(any(Notification.class));
        verify(repository).save(any(Notification.class));
    }

    @Test
    void sendFailureLeavesFailedNotificationWithErrorMessage() {
        NotificationService service = new NotificationService(repository, new SimpleMeterRegistry()) {
            @Override
            protected void simulateSend(Notification notification) {
                throw new IllegalStateException("provider unavailable");
            }
        };
        when(repository.existsByEventKey("event-2")).thenReturn(false);
        when(repository.saveAndFlush(any(Notification.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(repository.save(any(Notification.class))).thenAnswer(invocation -> invocation.getArgument(0));

        NotificationProcessingResult result = service.processAndSend(
                UUID.randomUUID(),
                UUID.randomUUID(),
                null,
                "event-2",
                "APPOINTMENT_CANCELLED",
                "appointment-service",
                "appointment.cancelled",
                "patient@mediqueue.test",
                NotificationChannel.EMAIL);

        assertThat(result).isEqualTo(NotificationProcessingResult.CREATED_FAILED);
        verify(repository).save(argThatNotificationStatus(NotificationStatus.FAILED));
    }

    @Test
    void duplicateEventDoesNotCreateSecondNotification() {
        NotificationService service = new NotificationService(repository, new SimpleMeterRegistry());
        when(repository.existsByEventKey("event-3")).thenReturn(true);

        NotificationProcessingResult result = service.processAndSend(
                UUID.randomUUID(),
                UUID.randomUUID(),
                null,
                "event-3",
                "APPOINTMENT_EXPIRED",
                "appointment-service",
                "appointment.expired",
                "patient@mediqueue.test",
                NotificationChannel.EMAIL);

        assertThat(result).isEqualTo(NotificationProcessingResult.DUPLICATE);
        verify(repository, never()).saveAndFlush(any(Notification.class));
        verify(repository, never()).save(any(Notification.class));
    }

    @Test
    void deterministicEventKeyIsStableWhenSourceEventIdIsMissing() {
        NotificationService service = new NotificationService(repository, new SimpleMeterRegistry());
        UUID appointmentId = UUID.randomUUID();
        UUID patientId = UUID.randomUUID();

        String first = service.buildEventKey(null, "APPOINTMENT_CONFIRMED", appointmentId, null, patientId, NotificationChannel.EMAIL);
        String second = service.buildEventKey(null, "APPOINTMENT_CONFIRMED", appointmentId, null, patientId, NotificationChannel.EMAIL);

        assertThat(first).isEqualTo(second);
    }

    private Notification argThatNotificationStatus(NotificationStatus status) {
        return org.mockito.ArgumentMatchers.argThat(notification ->
                notification != null && notification.getNotificationStatus() == status
                        && notification.getErrorMessage() != null);
    }
}
