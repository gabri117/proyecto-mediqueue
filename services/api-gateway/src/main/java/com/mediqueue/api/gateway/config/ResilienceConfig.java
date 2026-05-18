package com.mediqueue.api.gateway.config;

import java.time.Duration;

import org.springframework.cloud.circuitbreaker.resilience4j.ReactiveResilience4JCircuitBreakerFactory;
import org.springframework.cloud.circuitbreaker.resilience4j.Resilience4JConfigBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.timelimiter.TimeLimiterConfig;

@Configuration
public class ResilienceConfig {

	@Bean
	public org.springframework.cloud.client.circuitbreaker.Customizer<ReactiveResilience4JCircuitBreakerFactory> defaultCustomizer() {
		return factory -> factory.configureDefault(id -> new Resilience4JConfigBuilder(id)
				.circuitBreakerConfig(CircuitBreakerConfig.custom()
						.slidingWindowSize(5)
						.failureRateThreshold(50)
						.waitDurationInOpenState(Duration.ofSeconds(10))
						.permittedNumberOfCallsInHalfOpenState(3)
						.automaticTransitionFromOpenToHalfOpenEnabled(true)
						.build())
				.timeLimiterConfig(TimeLimiterConfig.custom()
						.timeoutDuration(Duration.ofSeconds(10))
						.build())
				.build());
	}
}
