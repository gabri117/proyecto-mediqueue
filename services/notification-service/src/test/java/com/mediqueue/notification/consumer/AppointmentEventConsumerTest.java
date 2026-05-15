package com.mediqueue.notification.consumer;

import com.mediqueue.notification.events.AppointmentEvent;
import com.mediqueue.notification.service.NonRetryableNotificationException;
import com.mediqueue.notification.service.NotificationProcessingResult;
import com.mediqueue.notification.service.NotificationService;
import com.rabbitmq.client.Channel;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AppointmentEventConsumerTest {

    private final NotificationService service = mock(NotificationService.class);
    private final AppointmentEventConsumer consumer = new AppointmentEventConsumer(service);
    private final Channel channel = mock(Channel.class);

    @Test
    void validEventAcksMessage() throws Exception {
        AppointmentEvent event = event();
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_SENT);

        consumer.handleAppointmentEvent(event, channel, 10L, "appointment.confirmed", false);

        verify(channel).basicAck(10L, false);
    }

    @Test
    void duplicateEventAcksMessage() throws Exception {
        AppointmentEvent event = event();
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.DUPLICATE);

        consumer.handleAppointmentEvent(event, channel, 11L, "appointment.confirmed", false);

        verify(channel).basicAck(11L, false);
    }

    @Test
    void controlledFailedNotificationAcksMessage() throws Exception {
        AppointmentEvent event = event();
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(NotificationProcessingResult.CREATED_FAILED);

        consumer.handleAppointmentEvent(event, channel, 12L, "appointment.cancelled", false);

        verify(channel).basicAck(12L, false);
    }

    @Test
    void irreversibleValidationRejectsWithoutRequeue() throws Exception {
        AppointmentEvent event = event();
        when(service.processAndSend(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new NonRetryableNotificationException("patientId is required"));

        consumer.handleAppointmentEvent(event, channel, 13L, "appointment.confirmed", false);

        verify(channel).basicReject(13L, false);
    }

    private AppointmentEvent event() {
        AppointmentEvent event = new AppointmentEvent();
        event.setEventId(UUID.randomUUID().toString());
        event.setEventType("APPOINTMENT_CONFIRMED");
        event.setAppointmentId(UUID.randomUUID());
        event.setPatientId(UUID.randomUUID());
        return event;
    }
}
