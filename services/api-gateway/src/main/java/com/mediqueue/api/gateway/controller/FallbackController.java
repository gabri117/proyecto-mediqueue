package com.mediqueue.api.gateway.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mediqueue.api.gateway.dto.ErrorResponse;

import reactor.core.publisher.Mono;

@RestController
public class FallbackController {

	@GetMapping("/fallback/patient")
	public Mono<ResponseEntity<ErrorResponse>> patientFallback() {
		return unavailable("patient-service");
	}

	@GetMapping("/fallback/schedule")
	public Mono<ResponseEntity<ErrorResponse>> scheduleFallback() {
		return unavailable("schedule-service");
	}

	@GetMapping("/fallback/appointment")
	public Mono<ResponseEntity<ErrorResponse>> appointmentFallback() {
		return unavailable("appointment-service");
	}

	@GetMapping("/fallback/payment")
	public Mono<ResponseEntity<ErrorResponse>> paymentFallback() {
		return unavailable("payment-service");
	}

	@GetMapping("/fallback/notification")
	public Mono<ResponseEntity<ErrorResponse>> notificationFallback() {
		return unavailable("notification-service");
	}

	private Mono<ResponseEntity<ErrorResponse>> unavailable(String serviceName) {
		return Mono.just(ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
				.body(ErrorResponse.serviceUnavailable(serviceName + " is temporarily unavailable")));
	}
}
