package com.mediqueue.api.gateway.controller;

import static org.hamcrest.Matchers.hasItem;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.test.web.reactive.server.WebTestClient;

@WebFluxTest(GatewayInfoController.class)
class GatewayInfoControllerTest {

	@Autowired
	private WebTestClient webTestClient;

	@Test
	void infoReturnsGatewayMetadata() {
		webTestClient.get()
				.uri("/gateway/info")
				.exchange()
				.expectStatus().isOk()
				.expectBody()
				.jsonPath("$.service").isEqualTo("mediqueue-api-gateway")
				.jsonPath("$.status").isEqualTo("UP")
				.jsonPath("$.routes").value(hasItem("/api/payments/**"));
	}
}
