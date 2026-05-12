package com.mediqueue.schedule.controller;

import com.mediqueue.schedule.dto.DentistRequest;
import com.mediqueue.schedule.dto.DentistResponse;
import com.mediqueue.schedule.service.DentistService;
import jakarta.validation.Valid;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/dentists")
@RequiredArgsConstructor
public class DentistController {

    private final DentistService dentistService;

    @PostMapping
    public ResponseEntity<DentistResponse> createDentist(@Valid @RequestBody DentistRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(dentistService.createDentist(request));
    }

    @GetMapping("/{id}")
    public ResponseEntity<DentistResponse> findById(@PathVariable UUID id) {
        return ResponseEntity.ok(dentistService.findById(id));
    }

    @GetMapping
    public ResponseEntity<DentistResponse> findByEmail(@RequestParam String email) {
        return ResponseEntity.ok(dentistService.findByEmail(email));
    }

    @PatchMapping("/{id}/deactivate")
    public ResponseEntity<DentistResponse> deactivate(@PathVariable UUID id) {
        return ResponseEntity.ok(dentistService.deactivate(id));
    }

    @PatchMapping("/{id}/activate")
    public ResponseEntity<DentistResponse> activate(@PathVariable UUID id) {
        return ResponseEntity.ok(dentistService.activate(id));
    }
}
