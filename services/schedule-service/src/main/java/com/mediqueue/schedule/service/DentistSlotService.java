package com.mediqueue.schedule.service;

import com.mediqueue.schedule.domain.DentistSlot;
import com.mediqueue.schedule.domain.enums.SlotDisplayStatus;
import com.mediqueue.schedule.dto.DentistSlotRequest;
import com.mediqueue.schedule.dto.DentistSlotResponse;
import com.mediqueue.schedule.repository.DentistSlotRepository;
import jakarta.persistence.EntityNotFoundException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class DentistSlotService {

    private final DentistSlotRepository dentistSlotRepository;

    @Transactional
    public DentistSlotResponse createSlot(DentistSlotRequest request) {
        DentistSlot slot = DentistSlot.builder()
                .dentistId(request.dentistId())
                .slotDate(request.slotDate())
                .startTime(request.startTime())
                .endTime(request.endTime())
                .status(SlotDisplayStatus.AVAILABLE)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        DentistSlot savedSlot = dentistSlotRepository.save(slot);
        return mapToResponse(savedSlot);
    }

    public DentistSlotResponse findById(UUID slotId) {
        DentistSlot slot = dentistSlotRepository.findById(slotId)
                .orElseThrow(() -> new EntityNotFoundException("Slot not found"));
        return mapToResponse(slot);
    }

    public List<DentistSlotResponse> findByDentistId(UUID dentistId) {
        return dentistSlotRepository.findByDentistId(dentistId)
                .stream()
                .map(this::mapToResponse)
                .toList();
    }

    public List<DentistSlotResponse> findAvailableSlots() {
        return dentistSlotRepository.findByStatus(SlotDisplayStatus.AVAILABLE)
                .stream()
                .map(this::mapToResponse)
                .toList();
    }

    @Transactional
    public DentistSlotResponse deactivate(UUID slotId) {
        DentistSlot slot = dentistSlotRepository.findById(slotId)
                .orElseThrow(() -> new EntityNotFoundException("Slot not found"));

        slot.setStatus(SlotDisplayStatus.BLOCKED);
        dentistSlotRepository.save(slot);
        return mapToResponse(slot);
    }

    @Transactional
    public DentistSlotResponse activate(UUID slotId) {
        DentistSlot slot = dentistSlotRepository.findById(slotId)
                .orElseThrow(() -> new EntityNotFoundException("Slot not found"));
        slot.setStatus(SlotDisplayStatus.AVAILABLE);
        dentistSlotRepository.save(slot);
        return mapToResponse(slot);
    }

    private DentistSlotResponse mapToResponse(DentistSlot slot) {
        return new DentistSlotResponse(
                slot.getSlotId(),
                slot.getDentistId(),
                slot.getSlotDate(),
                slot.getStartTime(),
                slot.getEndTime(),
                slot.getStatus().name(),
                slot.getCreatedAt(),
                slot.getUpdatedAt()
        );
    }
}
