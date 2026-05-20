package com.mediqueue.api.gateway.filter;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.server.ServerWebExchange;

import reactor.core.publisher.Mono;

@Component
public class CorrelationIdGlobalFilter implements GlobalFilter, Ordered {

	public static final String CORRELATION_ID_HEADER = "X-Correlation-Id";

	private static final Logger log = LoggerFactory.getLogger(CorrelationIdGlobalFilter.class);

	private final boolean accessLogEnabled;

	public CorrelationIdGlobalFilter(
			@Value("${mediqueue.gateway.access-log.enabled:false}") boolean accessLogEnabled) {
		this.accessLogEnabled = accessLogEnabled;
	}

	@Override
	public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
		String incomingCorrelationId = exchange.getRequest().getHeaders().getFirst(CORRELATION_ID_HEADER);
		String correlationId = StringUtils.hasText(incomingCorrelationId)
				? incomingCorrelationId
				: UUID.randomUUID().toString();

		ServerHttpRequest request = exchange.getRequest()
				.mutate()
				.header(CORRELATION_ID_HEADER, correlationId)
				.build();

		exchange.getResponse().beforeCommit(() -> {
			exchange.getResponse().getHeaders().set(CORRELATION_ID_HEADER, correlationId);
			return Mono.empty();
		});

		if (accessLogEnabled && log.isDebugEnabled()) {
			log.debug("Incoming request method={} path={} correlationId={}",
					request.getMethod(), request.getURI().getRawPath(), correlationId);
		}

		return chain.filter(exchange.mutate().request(request).build());
	}

	@Override
	public int getOrder() {
		return Ordered.HIGHEST_PRECEDENCE;
	}
}
