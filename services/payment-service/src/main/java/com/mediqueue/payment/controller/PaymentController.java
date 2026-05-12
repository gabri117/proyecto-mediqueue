package com.mediqueue.payment.controller;

import com.mediqueue.payment.domain.enums.PaymentStatus;
import com.mediqueue.payment.dto.PagedResponse;
import com.mediqueue.payment.dto.PaymentRequest;
import com.mediqueue.payment.dto.PaymentResponse;
import com.mediqueue.payment.service.PaymentProcessResult;
import com.mediqueue.payment.service.PaymentService;
import jakarta.validation.Valid;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@RequestMapping("/payments")
public class PaymentController {

    private final PaymentService paymentService;

    @PostMapping
    ResponseEntity<PaymentResponse> createPayment(
            @RequestHeader("X-Idempotency-Key") String idempotencyKey,
            @Valid @RequestBody PaymentRequest request) {
        PaymentProcessResult result = paymentService.processManualPayment(idempotencyKey, request);
        return ResponseEntity.status(result.httpStatus()).body(result.response());
    }

    @GetMapping("/{id}")
    PaymentResponse getPayment(@PathVariable UUID id) {
        return paymentService.getPayment(id);
    }

    @GetMapping
    ResponseEntity<PagedResponse<PaymentResponse>> getPayments(
            @RequestParam(required = false) UUID appointmentId,
            @RequestParam(required = false) PaymentStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentService.getPayments(appointmentId, status, page, size));
    }
}
