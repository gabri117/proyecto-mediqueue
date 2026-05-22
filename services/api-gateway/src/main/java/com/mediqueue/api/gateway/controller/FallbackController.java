package com.mediqueue.api.gateway.controller;

import java.net.URI;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.route.Route;
import org.springframework.cloud.gateway.support.ServerWebExchangeUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ServerWebExchange;

import com.mediqueue.api.gateway.dto.ErrorResponse;
import com.mediqueue.api.gateway.filter.CorrelationIdGlobalFilter;

import reactor.core.publisher.Mono;

@RestController
public class FallbackController {

	private static final Logger log = LoggerFactory.getLogger(FallbackController.class);

	@RequestMapping("/fallback/patient")
	public Mono<ResponseEntity<ErrorResponse>> patientFallback(ServerWebExchange exchange) {
		return unavailable("patient-service", exchange);
	}

	@RequestMapping("/fallback/schedule")
	public Mono<ResponseEntity<ErrorResponse>> scheduleFallback(ServerWebExchange exchange) {
		return unavailable("schedule-service", exchange);
	}

	@RequestMapping("/fallback/appointment")
	public Mono<ResponseEntity<ErrorResponse>> appointmentFallback(ServerWebExchange exchange) {
		return unavailable("appointment-service", exchange);
	}

	@RequestMapping("/fallback/payment")
	public Mono<ResponseEntity<ErrorResponse>> paymentFallback(ServerWebExchange exchange) {
		return unavailable("payment-service", exchange);
	}

	@RequestMapping("/fallback/notification")
	public Mono<ResponseEntity<ErrorResponse>> notificationFallback(ServerWebExchange exchange) {
		return unavailable("notification-service", exchange);
	}

	private Mono<ResponseEntity<ErrorResponse>> unavailable(String serviceName, ServerWebExchange exchange) {
		Route route = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_ROUTE_ATTR);
		URI upstream = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_REQUEST_URL_ATTR);
		Object originalRequestUrls = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_ORIGINAL_REQUEST_URL_ATTR);
		Throwable exception = exchange.getAttribute(ServerWebExchangeUtils.CIRCUITBREAKER_EXECUTION_EXCEPTION_ATTR);
		String correlationId = exchange.getRequest().getHeaders().getFirst(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER);
		String exceptionName = exception != null ? exception.getClass().getSimpleName() : "none";
		String exceptionMessage = exception != null ? exception.getMessage() : "none";
		String failureKind = classifyFailure(exception);

		log.warn("gateway_fallback service={} routeId={} routeUri={} upstream={} originalRequestUrls={} correlationId={} status={} failureKind={} exception={} message={}",
				serviceName,
				route != null ? route.getId() : "unknown",
				route != null ? route.getUri() : "unknown",
				upstream != null ? upstream : "unknown",
				originalRequestUrls != null ? originalRequestUrls : "unknown",
				correlationId,
				HttpStatus.SERVICE_UNAVAILABLE.value(),
				failureKind,
				exceptionName,
				exceptionMessage);

		return Mono.just(ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
				.body(ErrorResponse.serviceUnavailable(serviceName + " is temporarily unavailable")));
	}

	private String classifyFailure(Throwable exception) {
		if (exception == null) {
			return "unknown";
		}

		String text = exceptionText(exception);
		if (text.contains("bulkheadfullexception") || text.contains("bulkhead")) {
			return "bulkhead_full";
		}
		if (text.contains("callnotpermittedexception")) {
			return "circuit_open";
		}
		if (text.contains("timeoutexception") || text.contains("timeout")) {
			return "timeout";
		}
		if (text.contains("circuitbreakerstatuscodeexception") && text.contains("500")) {
			return "upstream_500";
		}
		if (text.contains("circuitbreakerstatuscodeexception") && text.contains("503")) {
			return "upstream_503";
		}
		if (text.contains("connectexception") || text.contains("connection refused")) {
			return "connect_error";
		}
		return "unknown";
	}

	private String exceptionText(Throwable exception) {
		StringBuilder builder = new StringBuilder();
		Throwable current = exception;
		while (current != null) {
			builder.append(current.getClass().getSimpleName()).append(':');
			if (current.getMessage() != null) {
				builder.append(current.getMessage());
			}
			builder.append('|');
			current = current.getCause();
		}
		return builder.toString().toLowerCase();
	}
}
