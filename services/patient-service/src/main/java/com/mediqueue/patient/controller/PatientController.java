package com.mediqueue.patient.controller;

import com.mediqueue.patient.dto.PatientRequest;
import com.mediqueue.patient.dto.PatientResponse;
import com.mediqueue.patient.service.PatientService;
import jakarta.validation.Valid;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/patients")
@RequiredArgsConstructor
public class PatientController {

    private final PatientService patientService;

    @PostMapping
    public ResponseEntity<PatientResponse> createPatient(@Valid @RequestBody PatientRequest request) {
        PatientResponse response = patientService.createPatient(request);
        return new ResponseEntity<>(response, HttpStatus.CREATED);
    }

    @GetMapping("/{id}")
    public ResponseEntity<PatientResponse> getPatientById(@PathVariable UUID id) {
        PatientResponse response = patientService.findById(id);
        return ResponseEntity.ok(response);
    }

    @GetMapping(params = "email")
    public ResponseEntity<PatientResponse> getPatientByEmail(@RequestParam String email) {
        PatientResponse response = patientService.findByEmail(email);
        return ResponseEntity.ok(response);
    }

    @PatchMapping("/{id}/deactivate")
    public ResponseEntity<PatientResponse> deactivatePatient(@PathVariable UUID id) {
        PatientResponse response = patientService.deactivate(id);
        return ResponseEntity.ok(response);
    }

    @PatchMapping("/{id}/activate")
    public ResponseEntity<PatientResponse> activatePatient(@PathVariable UUID id) {
        PatientResponse response = patientService.activate(id);
        return ResponseEntity.ok(response);
    }
}
