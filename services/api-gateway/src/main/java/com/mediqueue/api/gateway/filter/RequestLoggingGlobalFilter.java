package com.mediqueue.api.gateway.filter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;

import reactor.core.publisher.Mono;

@Component
public class RequestLoggingGlobalFilter implements GlobalFilter, Ordered {

	private static final Logger log = LoggerFactory.getLogger(RequestLoggingGlobalFilter.class);

	@Override
	public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
		long startedAt = System.nanoTime();
		String method = exchange.getRequest().getMethod().name();
		String path = exchange.getRequest().getURI().getRawPath();
		String correlationId = exchange.getRequest().getHeaders()
				.getFirst(CorrelationIdGlobalFilter.CORRELATION_ID_HEADER);

		log.info("Request started method={} path={} correlationId={}", method, path, correlationId);

		return chain.filter(exchange)
				.doFinally(signalType -> {
					long durationMs = (System.nanoTime() - startedAt) / 1_000_000;
					HttpStatusCode status = exchange.getResponse().getStatusCode();
					log.info("Request completed status={} method={} path={} durationMs={} correlationId={}",
							status != null ? status.value() : "NA", method, path, durationMs, correlationId);
				});
	}

	@Override
	public int getOrder() {
		return Ordered.HIGHEST_PRECEDENCE + 1;
	}
}
