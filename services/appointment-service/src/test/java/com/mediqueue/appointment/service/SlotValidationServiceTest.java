package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.ScheduleClient;
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

@SpringJUnitConfig(SlotValidationServiceTest.TestConfig.class)
class SlotValidationServiceTest {

    private final SlotValidationService slotValidationService;
    private final ScheduleClient scheduleClient;
    private final CacheManager cacheManager;

    @Autowired
    SlotValidationServiceTest(SlotValidationService slotValidationService,
                              ScheduleClient scheduleClient,
                              CacheManager cacheManager) {
        this.slotValidationService = slotValidationService;
        this.scheduleClient = scheduleClient;
        this.cacheManager = cacheManager;
    }

    @BeforeEach
    void setUp() {
        reset(scheduleClient);
        cacheManager.getCache("slots").clear();
    }

    @Test
    void validatesSlotOnceWhenResultIsCached() {
        UUID slotId = UUID.randomUUID();

        slotValidationService.validateSlotExists(slotId);
        slotValidationService.validateSlotExists(slotId);

        verify(scheduleClient, times(1)).validateSlotExists(slotId);
    }

    @Test
    void validatesSlotFromDirectDatabaseMode() {
        UUID slotId = UUID.randomUUID();
        LoadTestDirectValidationService directValidationService = mock(LoadTestDirectValidationService.class);
        org.mockito.Mockito.when(directValidationService.availableSlotExists(slotId)).thenReturn(true);
        SlotValidationService service = new SlotValidationService(scheduleClient, directValidationService, true);

        service.validateSlotExists(slotId);

        verify(directValidationService, times(1)).availableSlotExists(slotId);
        verify(scheduleClient, times(0)).validateSlotExists(slotId);
    }

    @Test
    void rejectsSlotFromDirectDatabaseModeWhenMissing() {
        UUID slotId = UUID.randomUUID();
        LoadTestDirectValidationService directValidationService = mock(LoadTestDirectValidationService.class);
        org.mockito.Mockito.when(directValidationService.availableSlotExists(slotId)).thenReturn(false);
        SlotValidationService service = new SlotValidationService(scheduleClient, directValidationService, true);

        assertThrows(ServiceValidationException.class, () -> service.validateSlotExists(slotId));
    }

    @Test
    void doesNotCacheWhenSlotValidationFails() {
        UUID slotId = UUID.randomUUID();
        doThrow(new ServiceValidationException("Slot not found"))
                .when(scheduleClient).validateSlotExists(slotId);

        assertThrows(ServiceValidationException.class,
                () -> slotValidationService.validateSlotExists(slotId));
        assertThrows(ServiceValidationException.class,
                () -> slotValidationService.validateSlotExists(slotId));

        verify(scheduleClient, times(2)).validateSlotExists(slotId);
    }

    @Configuration
    @EnableCaching
    static class TestConfig {

        @Bean
        CacheManager cacheManager() {
            return new ConcurrentMapCacheManager("slots");
        }

        @Bean
        ScheduleClient scheduleClient() {
            return mock(ScheduleClient.class);
        }

        @Bean
        SlotValidationService slotValidationService(ScheduleClient scheduleClient) {
            return new SlotValidationService(scheduleClient, mock(LoadTestDirectValidationService.class), false);
        }
    }
}
