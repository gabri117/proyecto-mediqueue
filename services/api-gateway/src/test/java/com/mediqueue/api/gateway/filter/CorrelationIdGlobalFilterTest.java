package com.mediqueue.api.gateway.filter;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.web.server.ServerWebExchange;

import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class CorrelationIdGlobalFilterTest {

	private final CorrelationIdGlobalFilter filter = new CorrelationIdGlobalFilter();

	@Test
	void addsCorrelationIdWhenMissing() {
		var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/gateway/info"));
		AtomicReference<ServerWebExchange> capturedExchange = new AtomicReference<>();
		GatewayFilterChain chain = filteredExchange -> {
			capturedExchange.set(filteredExchange);
			return Mono.empty();
		};

		StepVerifier.create(filter.filter(exchange, chain))
				.verifyComplete();

		String correlationId = capturedExchange.get().getRequest().getHeaders()
				.getFirst(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER);
		assertThat(correlationId).isNotBlank();
	}

	@Test
	void propagatesExistingCorrelationId() {
		var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/gateway/info")
				.header(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER, "corr-123"));
		AtomicReference<ServerWebExchange> capturedExchange = new AtomicReference<>();

		StepVerifier.create(filter.filter(exchange, filteredExchange -> {
			capturedExchange.set(filteredExchange);
			return Mono.empty();
		})).verifyComplete();

		assertThat(capturedExchange.get().getRequest().getHeaders()
				.getFirst(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER)).isEqualTo("corr-123");
	}
}
