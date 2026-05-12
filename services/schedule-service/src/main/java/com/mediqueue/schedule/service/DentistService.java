package com.mediqueue.schedule.service;

import com.mediqueue.schedule.domain.Dentist;
import com.mediqueue.schedule.domain.enums.DentistStatus;
import com.mediqueue.schedule.dto.DentistRequest;
import com.mediqueue.schedule.dto.DentistResponse;
import com.mediqueue.schedule.repository.DentistRepository;
import jakarta.persistence.EntityNotFoundException;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class DentistService {

    private final DentistRepository dentistRepository;

    @Transactional
    public DentistResponse createDentist(DentistRequest request) {
        Dentist dentist = Dentist.builder()
                .firstName(request.firstName())
                .lastName(request.lastName())
                .specialty(request.specialty())
                .email(request.email())
                .licenseNumber(request.licenseNumber())
                .status(DentistStatus.ACTIVE)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        Dentist savedDentist = dentistRepository.save(dentist);
        return mapToResponse(savedDentist);
    }

    public DentistResponse findById(UUID dentistId) {
        Dentist dentist = dentistRepository.findById(dentistId)
                .orElseThrow(() -> new EntityNotFoundException("Dentist not found"));
        return mapToResponse(dentist);
    }

    public DentistResponse findByEmail(String email) {
        Dentist dentist = dentistRepository.findByEmail(email)
                .orElseThrow(() -> new EntityNotFoundException("Dentist not found"));
        return mapToResponse(dentist);
    }

    @Transactional
    public DentistResponse deactivate(UUID dentistId) {
        Dentist dentist = dentistRepository.findById(dentistId)
                .orElseThrow(() -> new EntityNotFoundException("Dentist not found"));

        dentist.setStatus(DentistStatus.INACTIVE);
        dentist.setUpdatedAt(LocalDateTime.now());
        Dentist updatedDentist = dentistRepository.save(dentist);
        return mapToResponse(updatedDentist);
    }

    @Transactional
    public DentistResponse activate(UUID dentistId) {
        Dentist dentist = dentistRepository.findById(dentistId)
                .orElseThrow(() -> new EntityNotFoundException("Dentist not found"));

        dentist.setStatus(DentistStatus.ACTIVE);
        dentist.setUpdatedAt(LocalDateTime.now());
        Dentist updatedDentist = dentistRepository.save(dentist);
        return mapToResponse(updatedDentist);
    }

    private DentistResponse mapToResponse(Dentist dentist) {
        return new DentistResponse(
                dentist.getDentistId(),
                dentist.getFirstName(),
                dentist.getLastName(),
                dentist.getSpecialty(),
                dentist.getEmail(),
                dentist.getLicenseNumber(),
                dentist.getStatus().name(),
                dentist.getCreatedAt(),
                dentist.getUpdatedAt()
        );
    }
}
