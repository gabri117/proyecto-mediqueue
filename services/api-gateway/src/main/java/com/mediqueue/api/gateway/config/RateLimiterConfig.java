package com.mediqueue.api.gateway.config;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;
import reactor.core.publisher.Mono;

@Configuration
public class RateLimiterConfig {

	@Bean
	public KeyResolver clientIpOrHeaderKeyResolver() {
		return exchange -> {
			String clientId = exchange.getRequest().getHeaders().getFirst("X-Client-Id");
			if (StringUtils.hasText(clientId)) {
				return Mono.just(clientId.trim());
			}

			var remoteAddress = exchange.getRequest().getRemoteAddress();
			if (remoteAddress != null && remoteAddress.getAddress() != null) {
				return Mono.just(remoteAddress.getAddress().getHostAddress());
			}

			return Mono.just("anonymous");
		};
	}
}
