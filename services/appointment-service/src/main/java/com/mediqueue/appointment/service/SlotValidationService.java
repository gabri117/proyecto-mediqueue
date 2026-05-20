package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.ScheduleClient;
import com.mediqueue.appointment.exception.ServiceValidationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class SlotValidationService {

    private final ScheduleClient scheduleClient;
    private final LoadTestDirectValidationService directValidationService;
    private final boolean directDbValidationEnabled;

    public SlotValidationService(ScheduleClient scheduleClient,
                                 LoadTestDirectValidationService directValidationService,
                                 @Value("${mediqueue.loadtest.direct-db-validation-enabled:false}") boolean directDbValidationEnabled) {
        this.scheduleClient = scheduleClient;
        this.directValidationService = directValidationService;
        this.directDbValidationEnabled = directDbValidationEnabled;
    }

    @Cacheable(value = "slots", key = "#slotId", unless = "#result == false")
    public boolean validateSlotExists(UUID slotId) {
        if (directDbValidationEnabled) {
            if (!directValidationService.availableSlotExists(slotId)) {
                throw new ServiceValidationException("Slot not found or unavailable");
            }
            return true;
        }
        scheduleClient.validateSlotExists(slotId);
        return true;
    }
}
