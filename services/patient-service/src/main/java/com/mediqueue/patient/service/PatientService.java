package com.mediqueue.patient.service;

import com.mediqueue.patient.domain.Patient;
import com.mediqueue.patient.domain.enums.PatientStatus;
import com.mediqueue.patient.dto.PatientRequest;
import com.mediqueue.patient.dto.PatientResponse;
import com.mediqueue.patient.repository.PatientRepository;
import jakarta.persistence.EntityNotFoundException;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class PatientService {

    private final PatientRepository patientRepository;

    @Transactional
    public PatientResponse createPatient(PatientRequest request) {
        LocalDateTime now = LocalDateTime.now();

        Patient patient = Patient.builder()
                .firstName(request.firstName())
                .lastName(request.lastName())
                .email(request.email())
                .phone(request.phone())
                .documentNumber(request.documentNumber())
                .status(PatientStatus.ACTIVE)
                .createdAt(now)
                .updatedAt(now)
                .build();

        Patient savedPatient = patientRepository.save(patient);
        return mapToResponse(savedPatient);
    }

    public PatientResponse findById(UUID patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new EntityNotFoundException("Patient not found"));
        return mapToResponse(patient);
    }

    public PatientResponse findByEmail(String email) {
        Patient patient = patientRepository.findByEmail(email)
                .orElseThrow(() -> new EntityNotFoundException("Patient not found"));
        return mapToResponse(patient);
    }

    @Transactional
    public PatientResponse deactivate(UUID patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new EntityNotFoundException("Patient not found"));

        patient.setStatus(PatientStatus.INACTIVE);
        patient.setUpdatedAt(LocalDateTime.now());

        Patient updatedPatient = patientRepository.save(patient);
        return mapToResponse(updatedPatient);
    }

    @Transactional
    public PatientResponse activate(UUID patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new EntityNotFoundException("Patient not found"));

        patient.setStatus(PatientStatus.ACTIVE);
        patient.setUpdatedAt(LocalDateTime.now());

        Patient updatedPatient = patientRepository.save(patient);
        return mapToResponse(updatedPatient);
    }

    private PatientResponse mapToResponse(Patient patient) {
        return new PatientResponse(
                patient.getPatientId(),
                patient.getFirstName(),
                patient.getLastName(),
                patient.getEmail(),
                patient.getPhone(),
                patient.getDocumentNumber(),
                patient.getStatus(),
                patient.getCreatedAt(),
                patient.getUpdatedAt()
        );
    }
}
