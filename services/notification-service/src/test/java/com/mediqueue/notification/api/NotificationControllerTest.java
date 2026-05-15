package com.mediqueue.notification.api;

import com.mediqueue.notification.domain.NotificationStatus;
import com.mediqueue.notification.dto.NotificationResponse;
import com.mediqueue.notification.service.NotificationService;
import com.mediqueue.notification.service.NotificationService.NotificationNotFoundException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(NotificationController.class)
class NotificationControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private NotificationService notificationService;

    @Test
    void getNotificationsReturnsPagedResponse() throws Exception {
        when(notificationService.search(isNull(), isNull(), isNull(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(response())));

        mockMvc.perform(get("/notifications?page=0&size=20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[0].notificationStatus").value("SENT"));
    }

    @Test
    void filtersByPatientId() throws Exception {
        UUID patientId = UUID.randomUUID();
        when(notificationService.search(eq(patientId), isNull(), isNull(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(response())));

        mockMvc.perform(get("/notifications?patientId=" + patientId))
                .andExpect(status().isOk());
    }

    @Test
    void filtersByAppointmentId() throws Exception {
        UUID appointmentId = UUID.randomUUID();
        when(notificationService.search(isNull(), eq(appointmentId), isNull(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(response())));

        mockMvc.perform(get("/notifications?appointmentId=" + appointmentId))
                .andExpect(status().isOk());
    }

    @Test
    void filtersByStatus() throws Exception {
        when(notificationService.search(isNull(), isNull(), eq(NotificationStatus.SENT), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(response())));

        mockMvc.perform(get("/notifications?status=SENT"))
                .andExpect(status().isOk());
    }

    @Test
    void getNotificationByIdReturns404WhenMissing() throws Exception {
        UUID id = UUID.randomUUID();
        when(notificationService.findById(id)).thenThrow(new NotificationNotFoundException(id));

        mockMvc.perform(get("/notifications/" + id))
                .andExpect(status().isNotFound());
    }

    private NotificationResponse response() {
        return NotificationResponse.builder()
                .notificationId(UUID.randomUUID())
                .patientId(UUID.randomUUID())
                .appointmentId(UUID.randomUUID())
                .eventType("APPOINTMENT_CONFIRMED")
                .notificationStatus(NotificationStatus.SENT)
                .destination("patient@mediqueue.test")
                .attemptCount(1)
                .createdAt(LocalDateTime.now())
                .build();
    }
}
