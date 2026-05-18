package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.PatientClient;
import com.mediqueue.appointment.exception.ServiceValidationException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.concurrent.ConcurrentMapCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

@SpringJUnitConfig(PatientValidationServiceTest.TestConfig.class)
class PatientValidationServiceTest {

    private final PatientValidationService patientValidationService;
    private final PatientClient patientClient;
    private final CacheManager cacheManager;

    @Autowired
    PatientValidationServiceTest(PatientValidationService patientValidationService,
                                 PatientClient patientClient,
                                 CacheManager cacheManager) {
        this.patientValidationService = patientValidationService;
        this.patientClient = patientClient;
        this.cacheManager = cacheManager;
    }

    @BeforeEach
    void setUp() {
        reset(patientClient);
        cacheManager.getCache("patients").clear();
    }

    @Test
    void validatesPatientOnceWhenResultIsCached() {
        UUID patientId = UUID.randomUUID();

        patientValidationService.validatePatientExists(patientId);
        patientValidationService.validatePatientExists(patientId);

        verify(patientClient, times(1)).validatePatientExists(patientId);
    }

    @Test
    void doesNotCacheWhenPatientValidationFails() {
        UUID patientId = UUID.randomUUID();
        doThrow(new ServiceValidationException("Patient not found"))
                .when(patientClient).validatePatientExists(patientId);

        assertThrows(ServiceValidationException.class,
                () -> patientValidationService.validatePatientExists(patientId));
        assertThrows(ServiceValidationException.class,
                () -> patientValidationService.validatePatientExists(patientId));

        verify(patientClient, times(2)).validatePatientExists(patientId);
    }

    @Configuration
    @EnableCaching
    static class TestConfig {

        @Bean
        CacheManager cacheManager() {
            return new ConcurrentMapCacheManager("patients");
        }

        @Bean
        PatientClient patientClient() {
            return mock(PatientClient.class);
        }

        @Bean
        PatientValidationService patientValidationService(PatientClient patientClient) {
            return new PatientValidationService(patientClient);
        }
    }
}
