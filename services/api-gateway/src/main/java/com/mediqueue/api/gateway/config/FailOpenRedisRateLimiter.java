package com.mediqueue.api.gateway.config;

import java.time.Duration;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.ratelimit.RateLimiter.Response;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.cloud.gateway.support.ConfigurationService;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public class FailOpenRedisRateLimiter extends RedisRateLimiter {

	private static final Duration REDIS_CHECK_TIMEOUT = Duration.ofMillis(500);
	private static final Duration FAIL_OPEN_COOLDOWN = Duration.ofSeconds(5);
	private static final Logger failOpenLog = LoggerFactory.getLogger("com.mediqueue.api.gateway.ratelimit.failopen");

	private final ReactiveStringRedisTemplate redisTemplate;
	private final RedisScript<List<Long>> script;
	private final String redisHost;
	private final AtomicLong redisUnavailableUntilEpochMillis = new AtomicLong();

	public FailOpenRedisRateLimiter(
			ReactiveStringRedisTemplate redisTemplate,
			RedisScript<List<Long>> script,
			ConfigurationService configurationService,
			String redisHost) {
		super(redisTemplate, script, configurationService);
		this.redisTemplate = redisTemplate;
		this.script = script;
		this.redisHost = redisHost;
	}

	@Override
	public Mono<Response> isAllowed(String routeId, String id) {
		Config config;
		try {
			config = routeConfig(routeId);
			List<String> keys = getRedisKeys(id, routeId);
			List<String> scriptArgs = List.of(
					String.valueOf(config.getReplenishRate()),
					String.valueOf(config.getBurstCapacity()),
					"",
					String.valueOf(config.getRequestedTokens()));

			if (isRedisInCooldown()) {
				return Mono.just(new Response(true, getHeaders(config, -1L)));
			}

			return redisHostAvailable()
					.flatMapMany(available -> {
						if (!available) {
							return allowWithWarn(routeId, id, new IllegalStateException("RedisHostUnavailable"));
						}
						return redisResults(routeId, id, keys, scriptArgs)
								.timeout(REDIS_CHECK_TIMEOUT)
								.doOnNext(result -> redisUnavailableUntilEpochMillis.set(0))
								.onErrorResume(ex -> allowWithWarn(routeId, id, ex));
					})
					.reduce(new ArrayList<Long>(), (results, values) -> {
						results.addAll(values);
						return results;
					})
					.map(results -> responseFromResults(routeId, id, config, results));
		}
		catch (Exception ex) {
			failOpenLog.warn("rate_limiter_redis_unavailable routeId={} key={} action=allow reason={}",
					logValue(routeId), logValue(id), rootCause(ex).getClass().getSimpleName());
			return Mono.just(new Response(true, Map.of()));
		}
	}

	protected Flux<List<Long>> redisResults(String routeId, String id, List<String> keys, List<String> scriptArgs) {
		return redisTemplate.execute(script, keys, scriptArgs);
	}

	private Mono<Boolean> redisHostAvailable() {
		CompletableFuture<Boolean> lookup = CompletableFuture.supplyAsync(() -> {
				try {
					InetAddress.getAllByName(redisHost);
					return true;
				}
				catch (Exception ex) {
					return false;
				}
				})
				.completeOnTimeout(false, REDIS_CHECK_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS)
				.exceptionally(ex -> false);

		return Mono.fromFuture(lookup);
	}

	private Flux<List<Long>> allowWithWarn(String routeId, String id, Throwable ex) {
		redisUnavailableUntilEpochMillis.set(System.currentTimeMillis() + FAIL_OPEN_COOLDOWN.toMillis());
		failOpenLog.warn("rate_limiter_redis_unavailable routeId={} key={} action=allow reason={}",
				logValue(routeId), logValue(id), rootCause(ex).getClass().getSimpleName());
		return Flux.just(List.of(1L, -1L));
	}

	private Response responseFromResults(String routeId, String id, Config config, List<Long> results) {
		if (results.size() < 2) {
			failOpenLog.warn("rate_limiter_redis_unavailable routeId={} key={} action=allow reason=EmptyRedisResponse",
					logValue(routeId), logValue(id));
			return new Response(true, getHeaders(config, -1L));
		}

		boolean allowed = results.get(0) == 1L;
		Long tokensLeft = results.get(1);
		return new Response(allowed, getHeaders(config, tokensLeft));
	}

	private Config routeConfig(String routeId) {
		Config config = getConfig().get(routeId);
		if (config == null) {
			config = getConfig().get("defaultFilters");
		}
		if (config == null) {
			throw new IllegalArgumentException("No rate limiter configuration found for route " + routeId);
		}
		return config;
	}

	private static List<String> getRedisKeys(String id, String routeId) {
		String prefix = "request_rate_limiter.{" + routeId + "." + id + "}.";
		return Arrays.asList(prefix + "tokens", prefix + "timestamp");
	}

	private boolean isRedisInCooldown() {
		return System.currentTimeMillis() < redisUnavailableUntilEpochMillis.get();
	}

	private static Throwable rootCause(Throwable ex) {
		Throwable current = ex;
		while (current.getCause() != null) {
			current = current.getCause();
		}
		return current;
	}

	private static String logValue(String value) {
		if (value == null || value.isBlank()) {
			return "unknown";
		}
		return value.replace('\r', '_').replace('\n', '_');
	}
}
