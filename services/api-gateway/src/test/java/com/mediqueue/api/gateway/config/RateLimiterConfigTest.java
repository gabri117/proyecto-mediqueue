package com.mediqueue.api.gateway.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.InetSocketAddress;

import org.junit.jupiter.api.Test;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;

import reactor.test.StepVerifier;

class RateLimiterConfigTest {

	private final RateLimiterConfig config = new RateLimiterConfig();

	@Test
	void keyResolverUsesClientIdHeaderWhenPresent() {
		var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/payments")
				.header("X-Client-Id", "test-client-1"));

		StepVerifier.create(config.clientIpOrHeaderKeyResolver().resolve(exchange))
				.expectNext("test-client-1")
				.verifyComplete();
	}

	@Test
	void keyResolverUsesForwardedForWhenClientIdIsMissing() {
		var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/payments")
				.header("X-Forwarded-For", " 203.0.113.10, 10.0.0.5 "));

		StepVerifier.create(config.clientIpOrHeaderKeyResolver().resolve(exchange))
				.expectNext("203.0.113.10")
				.verifyComplete();
	}

	@Test
	void keyResolverUsesRealIpWhenForwardedForIsBlank() {
		var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/payments")
				.header("X-Forwarded-For", " ")
				.header("X-Real-IP", " 198.51.100.7 "));

		StepVerifier.create(config.clientIpOrHeaderKeyResolver().resolve(exchange))
				.expectNext("198.51.100.7")
				.verifyComplete();
	}

	@Test
	void keyResolverFallsBackToRemoteAddress() {
		var request = MockServerHttpRequest.get("/api/payments")
				.remoteAddress(new InetSocketAddress("127.0.0.1", 54321))
				.build();

		StepVerifier.create(config.clientIpOrHeaderKeyResolver().resolve(MockServerWebExchange.from(request)))
				.assertNext(key -> assertThat(key).isIn("127.0.0.1", "0:0:0:0:0:0:0:1"))
				.verifyComplete();
	}
}
