package com.mediqueue.notification.api;

import com.mediqueue.notification.dto.NotificationResponse;
import com.mediqueue.notification.service.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;

    @GetMapping
    public Page<NotificationResponse> findAll(
            @PageableDefault(size = 20, sort = "createdAt") Pageable pageable) {
        return notificationService.findAll(pageable);
    }

    @GetMapping("/{id}")
    public ResponseEntity<NotificationResponse> findById(@PathVariable UUID id) {
        return ResponseEntity.ok(notificationService.findById(id));
    }

    @GetMapping("/patient/{patientId}")
    public Page<NotificationResponse> findByPatient(
            @PathVariable UUID patientId,
            @PageableDefault(size = 20, sort = "createdAt") Pageable pageable) {
        return notificationService.findByPatientId(patientId, pageable);
    }
}
