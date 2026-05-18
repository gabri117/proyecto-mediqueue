package com.mediqueue.appointment.service;

import com.mediqueue.appointment.client.ScheduleClient;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class SlotValidationService {

    private final ScheduleClient scheduleClient;

    public SlotValidationService(ScheduleClient scheduleClient) {
        this.scheduleClient = scheduleClient;
    }

    @Cacheable(value = "slots", key = "#slotId", unless = "#result == false")
    public boolean validateSlotExists(UUID slotId) {
        scheduleClient.validateSlotExists(slotId);
        return true;
    }
}
