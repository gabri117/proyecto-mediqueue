package com.mediqueue.api.gateway.config;

import java.util.List;

public final class GatewayRoutesConfig {

	private GatewayRoutesConfig() {
	}

	public static List<String> documentedRoutes() {
		return List.of(
				"/api/patients/**",
				"/api/dentists/**",
				"/api/dentist-slots/**",
				"/api/appointments/**",
				"/api/payments/**",
				"/api/notifications/**");
	}
}
