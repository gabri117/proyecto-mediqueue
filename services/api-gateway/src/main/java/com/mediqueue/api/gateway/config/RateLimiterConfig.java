package com.mediqueue.api.gateway.config;

import java.util.List;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.cloud.gateway.support.ConfigurationService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.util.StringUtils;
import reactor.core.publisher.Mono;

@Configuration
public class RateLimiterConfig {

	@Bean(name = "redisRateLimiter")
	@Primary
	public RedisRateLimiter redisRateLimiter(
			ReactiveStringRedisTemplate redisTemplate,
			@Qualifier(RedisRateLimiter.REDIS_SCRIPT_NAME) RedisScript<List<Long>> redisScript,
			ConfigurationService configurationService,
			@Value("${spring.data.redis.host}") String redisHost) {
		return new FailOpenRedisRateLimiter(redisTemplate, redisScript, configurationService, redisHost);
	}

	@Bean
	public KeyResolver clientIpOrHeaderKeyResolver() {
		return exchange -> {
			var headers = exchange.getRequest().getHeaders();

			String clientId = clean(headers.getFirst("X-Client-Id"));
			if (clientId != null) {
				return Mono.just(clientId);
			}

			String forwardedFor = firstForwardedFor(headers.getFirst("X-Forwarded-For"));
			if (forwardedFor != null) {
				return Mono.just(forwardedFor);
			}

			String realIp = clean(headers.getFirst("X-Real-IP"));
			if (realIp != null) {
				return Mono.just(realIp);
			}

			var remoteAddress = exchange.getRequest().getRemoteAddress();
			if (remoteAddress != null && remoteAddress.getAddress() != null) {
				return Mono.just(remoteAddress.getAddress().getHostAddress());
			}

			return Mono.just("anonymous");
		};
	}

	private static String firstForwardedFor(String forwardedFor) {
		String value = clean(forwardedFor);
		if (value == null) {
			return null;
		}

		return clean(value.split(",", 2)[0]);
	}

	private static String clean(String value) {
		if (!StringUtils.hasText(value)) {
			return null;
		}

		String trimmed = value.trim();
		return StringUtils.hasText(trimmed) ? trimmed : null;
	}
}
