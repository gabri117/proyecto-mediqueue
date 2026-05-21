package com.mediqueue.api.gateway.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter.Config;
import org.springframework.cloud.gateway.support.ConfigurationService;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;

import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;

class FailOpenRedisRateLimiterTest {

	@Test
	void isAllowedAllowsRequestWhenRedisCheckFails() {
		var rateLimiter = new FailingRateLimiter();
		rateLimiter.getConfig().put("patient-service", new Config()
				.setReplenishRate(50)
				.setBurstCapacity(100)
				.setRequestedTokens(1));

		StepVerifier.create(rateLimiter.isAllowed("patient-service", "vu-1"))
				.assertNext(response -> assertThat(response.isAllowed()).isTrue())
				.verifyComplete();
	}

	private static final class FailingRateLimiter extends FailOpenRedisRateLimiter {

		private FailingRateLimiter() {
			super(mock(ReactiveStringRedisTemplate.class), mock(RedisScript.class), mock(ConfigurationService.class), "localhost", true);
		}

		@Override
		protected Flux<java.util.List<Long>> redisResults(
				String routeId,
				String id,
				java.util.List<String> keys,
				java.util.List<String> scriptArgs) {
			return Flux.error(new IllegalStateException("redis unavailable"));
		}
	}
}
