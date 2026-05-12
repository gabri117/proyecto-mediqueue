package com.mediqueue.appointment.controller;

import com.mediqueue.appointment.dto.AppointmentRequest;
import com.mediqueue.appointment.dto.AppointmentResponse;
import com.mediqueue.appointment.service.AppointmentService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * REST controller exposing appointment operations.
 *
 * <p>This controller is a thin HTTP adapter — all business logic is
 * delegated to {@link AppointmentService}.</p>
 *
 * @since 0.0.1
 */
@RestController
@RequestMapping("/appointments")
public class AppointmentController {

    private final AppointmentService appointmentService;

    public AppointmentController(AppointmentService appointmentService) {
        this.appointmentService = appointmentService;
    }

    /**
     * Creates a new appointment with idempotency protection.
     *
     * @param idempotencyKey client-supplied idempotency key via {@code X-Idempotency-Key} header
     * @param request        the appointment creation payload
     * @return 201 Created with the appointment response body
     */
    @PostMapping
    public ResponseEntity<AppointmentResponse> create(
            @RequestHeader("X-Idempotency-Key") String idempotencyKey,
            @RequestBody @Valid AppointmentRequest request) {

        AppointmentResponse response = appointmentService.createAppointment(request, idempotencyKey);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * Retrieves a single appointment by its unique identifier.
     *
     * @param id the appointment UUID
     * @return 200 OK with the appointment response body
     */
    @GetMapping("/{id}")
    public ResponseEntity<AppointmentResponse> findById(@PathVariable UUID id) {
        return ResponseEntity.ok(appointmentService.findById(id));
    }

    /**
     * Retrieves all appointments for a given patient.
     *
     * @param patientId the patient's UUID
     * @return 200 OK with the list of appointment responses
     */
    @GetMapping
    public ResponseEntity<List<AppointmentResponse>> findByPatient(@RequestParam UUID patientId) {
        return ResponseEntity.ok(appointmentService.findByPatientId(patientId));
    }
}
