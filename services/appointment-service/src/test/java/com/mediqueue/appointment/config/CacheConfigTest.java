package com.mediqueue.appointment.config;

import org.junit.jupiter.api.Test;
import org.springframework.cache.Cache;
import org.springframework.cache.concurrent.ConcurrentMapCache;
import org.springframework.cache.interceptor.CacheErrorHandler;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class CacheConfigTest {

    private final CacheErrorHandler cacheErrorHandler = new CacheConfig().errorHandler();
    private final Cache cache = new ConcurrentMapCache("patients");
    private final RuntimeException redisFailure = new RuntimeException("redis unavailable");

    @Test
    void cacheErrorHandlerDoesNotPropagateGetErrors() {
        assertDoesNotThrow(() -> cacheErrorHandler.handleCacheGetError(redisFailure, cache, "patient-id"));
    }

    @Test
    void cacheErrorHandlerDoesNotPropagatePutErrors() {
        assertDoesNotThrow(() -> cacheErrorHandler.handleCachePutError(redisFailure, cache, "patient-id", true));
    }

    @Test
    void cacheErrorHandlerDoesNotPropagateEvictErrors() {
        assertDoesNotThrow(() -> cacheErrorHandler.handleCacheEvictError(redisFailure, cache, "patient-id"));
    }

    @Test
    void cacheErrorHandlerDoesNotPropagateClearErrors() {
        assertDoesNotThrow(() -> cacheErrorHandler.handleCacheClearError(redisFailure, cache));
    }
}
