package com.mediqueue.api.gateway.config;

import java.time.Duration;

import org.springframework.cloud.circuitbreaker.resilience4j.ReactiveResilience4JCircuitBreakerFactory;
import org.springframework.cloud.circuitbreaker.resilience4j.ReactiveResilience4jBulkheadProvider;
import org.springframework.cloud.circuitbreaker.resilience4j.Resilience4JConfigBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.github.resilience4j.bulkhead.BulkheadConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.timelimiter.TimeLimiterConfig;

@Configuration
public class ResilienceConfig {

	@Value("${mediqueue.gateway.circuitbreaker.sliding-window-size:100}")
	private int slidingWindowSize;

	@Value("${mediqueue.gateway.circuitbreaker.minimum-number-of-calls:50}")
	private int minimumNumberOfCalls;

	@Value("${mediqueue.gateway.circuitbreaker.failure-rate-threshold:80}")
	private float failureRateThreshold;

	@Value("${mediqueue.gateway.circuitbreaker.wait-duration-open-seconds:5}")
	private long waitDurationOpenSeconds;

	@Value("${mediqueue.gateway.circuitbreaker.half-open-calls:10}")
	private int halfOpenCalls;

	@Value("${mediqueue.gateway.timelimiter.timeout-seconds:10}")
	private long timeoutSeconds;

	@Value("${mediqueue.gateway.bulkhead.default.max-concurrent-calls:200}")
	private int defaultBulkheadMaxConcurrentCalls;

	@Value("${mediqueue.gateway.bulkhead.appointment.max-concurrent-calls:1000}")
	private int appointmentBulkheadMaxConcurrentCalls;

	@Value("${mediqueue.gateway.bulkhead.max-wait-millis:0}")
	private long bulkheadMaxWaitMillis;

	@Bean
	public org.springframework.cloud.client.circuitbreaker.Customizer<ReactiveResilience4JCircuitBreakerFactory> defaultCustomizer() {
		return factory -> factory.configureDefault(id -> new Resilience4JConfigBuilder(id)
				.circuitBreakerConfig(CircuitBreakerConfig.custom()
						.slidingWindowSize(slidingWindowSize)
						.minimumNumberOfCalls(minimumNumberOfCalls)
						.failureRateThreshold(failureRateThreshold)
						.waitDurationInOpenState(Duration.ofSeconds(waitDurationOpenSeconds))
						.permittedNumberOfCallsInHalfOpenState(halfOpenCalls)
						.automaticTransitionFromOpenToHalfOpenEnabled(true)
						.build())
				.timeLimiterConfig(TimeLimiterConfig.custom()
						.timeoutDuration(Duration.ofSeconds(timeoutSeconds))
						.build())
				.build());
	}

	@Bean
	public org.springframework.cloud.client.circuitbreaker.Customizer<ReactiveResilience4jBulkheadProvider> bulkheadCustomizer() {
		BulkheadConfig defaultBulkhead = BulkheadConfig.custom()
				.maxConcurrentCalls(defaultBulkheadMaxConcurrentCalls)
				.maxWaitDuration(Duration.ofMillis(bulkheadMaxWaitMillis))
				.build();
		BulkheadConfig appointmentBulkhead = BulkheadConfig.custom()
				.maxConcurrentCalls(appointmentBulkheadMaxConcurrentCalls)
				.maxWaitDuration(Duration.ofMillis(bulkheadMaxWaitMillis))
				.build();

		return provider -> {
			provider.configureDefault(id -> new org.springframework.cloud.circuitbreaker.resilience4j.Resilience4jBulkheadConfigurationBuilder()
					.bulkheadConfig(defaultBulkhead)
					.build());
			provider.configure(builder -> builder.bulkheadConfig(appointmentBulkhead), "appointment-service");
		};
	}
}
