package com.mediqueue.api.gateway.controller;

import java.net.URI;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.route.Route;
import org.springframework.cloud.gateway.support.ServerWebExchangeUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ServerWebExchange;

import com.mediqueue.api.gateway.dto.ErrorResponse;
import com.mediqueue.api.gateway.filter.CorrelationIdGlobalFilter;

import reactor.core.publisher.Mono;

@RestController
public class FallbackController {

	private static final Logger log = LoggerFactory.getLogger(FallbackController.class);

	@GetMapping("/fallback/patient")
	public Mono<ResponseEntity<ErrorResponse>> patientFallback(ServerWebExchange exchange) {
		return unavailable("patient-service", exchange);
	}

	@GetMapping("/fallback/schedule")
	public Mono<ResponseEntity<ErrorResponse>> scheduleFallback(ServerWebExchange exchange) {
		return unavailable("schedule-service", exchange);
	}

	@GetMapping("/fallback/appointment")
	public Mono<ResponseEntity<ErrorResponse>> appointmentFallback(ServerWebExchange exchange) {
		return unavailable("appointment-service", exchange);
	}

	@GetMapping("/fallback/payment")
	public Mono<ResponseEntity<ErrorResponse>> paymentFallback(ServerWebExchange exchange) {
		return unavailable("payment-service", exchange);
	}

	@GetMapping("/fallback/notification")
	public Mono<ResponseEntity<ErrorResponse>> notificationFallback(ServerWebExchange exchange) {
		return unavailable("notification-service", exchange);
	}

	private Mono<ResponseEntity<ErrorResponse>> unavailable(String serviceName, ServerWebExchange exchange) {
		Route route = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_ROUTE_ATTR);
		URI upstream = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_REQUEST_URL_ATTR);
		Throwable exception = exchange.getAttribute(ServerWebExchangeUtils.CIRCUITBREAKER_EXECUTION_EXCEPTION_ATTR);
		String correlationId = exchange.getRequest().getHeaders().getFirst(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER);
		String exceptionName = exception != null ? exception.getClass().getSimpleName() : "none";
		String exceptionMessage = exception != null ? exception.getMessage() : "none";

		log.warn("gateway_fallback service={} routeId={} upstream={} correlationId={} status={} exception={} message={}",
				serviceName,
				route != null ? route.getId() : "unknown",
				upstream != null ? upstream : "unknown",
				correlationId,
				HttpStatus.SERVICE_UNAVAILABLE.value(),
				exceptionName,
				exceptionMessage);

		return Mono.just(ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
				.body(ErrorResponse.serviceUnavailable(serviceName + " is temporarily unavailable")));
	}
}
