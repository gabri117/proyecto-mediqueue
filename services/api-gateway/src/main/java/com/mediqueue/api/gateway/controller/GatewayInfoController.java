package com.mediqueue.api.gateway.controller;

import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mediqueue.api.gateway.config.GatewayRoutesConfig;

@RestController
public class GatewayInfoController {

	@GetMapping("/gateway/info")
	public Map<String, Object> info() {
		return Map.of(
				"service", "mediqueue-api-gateway",
				"status", "UP",
				"routes", GatewayRoutesConfig.documentedRoutes());
	}

	@GetMapping("/gateway/routes")
	public List<Map<String, String>> routes() {
		return List.of(
				route("/api/patients/**", "patient-service", "/patients/**"),
				route("/api/dentists/**", "schedule-service", "/dentists/**"),
				route("/api/dentist-slots/**", "schedule-service", "/dentist-slots/**"),
				route("/api/appointments/**", "appointment-service", "/appointments/**"),
				route("/api/payments/**", "payment-service", "/payments/**"),
				route("/api/notifications/**", "notification-service", "/notifications/**"));
	}

	private Map<String, String> route(String path, String service, String forwardsTo) {
		return Map.of("path", path, "service", service, "forwardsTo", forwardsTo);
	}
}
