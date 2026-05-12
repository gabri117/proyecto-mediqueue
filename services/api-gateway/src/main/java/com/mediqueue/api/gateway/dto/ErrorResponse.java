package com.mediqueue.api.gateway.dto;

import java.time.Instant;

public record ErrorResponse(String code, String message, Instant timestamp) {

	public static ErrorResponse serviceUnavailable(String message) {
		return new ErrorResponse("SERVICE_UNAVAILABLE", message, Instant.now());
	}
}
