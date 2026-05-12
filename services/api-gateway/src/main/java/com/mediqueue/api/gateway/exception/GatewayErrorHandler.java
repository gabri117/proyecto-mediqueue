package com.mediqueue.api.gateway.exception;

import java.nio.charset.StandardCharsets;

import org.springframework.core.annotation.Order;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebExceptionHandler;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.api.gateway.dto.ErrorResponse;

import reactor.core.publisher.Mono;

@Component
@Order(-2)
public class GatewayErrorHandler implements WebExceptionHandler {

	private final ObjectMapper objectMapper;

	public GatewayErrorHandler(ObjectMapper objectMapper) {
		this.objectMapper = objectMapper;
	}

	@Override
	public Mono<Void> handle(ServerWebExchange exchange, Throwable ex) {
		if (exchange.getResponse().isCommitted()) {
			return Mono.error(ex);
		}

		exchange.getResponse().setStatusCode(HttpStatus.SERVICE_UNAVAILABLE);
		exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);

		ErrorResponse error = ErrorResponse.serviceUnavailable("Upstream service is temporarily unavailable");
		byte[] bytes;
		try {
			bytes = objectMapper.writeValueAsBytes(error);
		}
		catch (Exception serializationException) {
			bytes = "{\"code\":\"SERVICE_UNAVAILABLE\",\"message\":\"Upstream service is temporarily unavailable\"}"
					.getBytes(StandardCharsets.UTF_8);
		}

		DataBuffer buffer = exchange.getResponse().bufferFactory().wrap(bytes);
		return exchange.getResponse().writeWith(Mono.just(buffer));
	}
}
