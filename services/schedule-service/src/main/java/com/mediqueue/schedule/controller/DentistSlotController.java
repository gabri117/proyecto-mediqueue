package com.mediqueue.schedule.controller;

import com.mediqueue.schedule.dto.DentistSlotRequest;
import com.mediqueue.schedule.dto.DentistSlotResponse;
import com.mediqueue.schedule.service.DentistSlotService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/slots")
@RequiredArgsConstructor
public class DentistSlotController {

    private final DentistSlotService dentistSlotService;

    @PostMapping
    public ResponseEntity<DentistSlotResponse> createSlot(@Valid @RequestBody DentistSlotRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(dentistSlotService.createSlot(request));
    }

    @GetMapping("/{id}")
    public ResponseEntity<DentistSlotResponse> findById(@PathVariable UUID id) {
        return ResponseEntity.ok(dentistSlotService.findById(id));
    }

    @GetMapping("/dentist/{dentistId}")
    public ResponseEntity<List<DentistSlotResponse>> findByDentistId(@PathVariable UUID dentistId) {
        return ResponseEntity.ok(dentistSlotService.findByDentistId(dentistId));
    }

    @GetMapping("/available")
    public ResponseEntity<List<DentistSlotResponse>> findAvailableSlots() {
        return ResponseEntity.ok(dentistSlotService.findAvailableSlots());
    }

    @PatchMapping("/{id}/deactivate")
    public ResponseEntity<DentistSlotResponse> deactivate(@PathVariable UUID id) {
        return ResponseEntity.ok(dentistSlotService.deactivate(id));
    }

    @PatchMapping("/{slotId}/activate")
    public ResponseEntity<DentistSlotResponse> activate(@PathVariable UUID slotId) {
        return ResponseEntity.ok(dentistSlotService.activate(slotId));
    }
}
