package com.mediqueue.schedule.repository;

import com.mediqueue.schedule.domain.DentistSlot;
import com.mediqueue.schedule.domain.enums.SlotDisplayStatus;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface DentistSlotRepository extends JpaRepository<DentistSlot, UUID> {

    List<DentistSlot> findByDentistId(UUID dentistId);

    List<DentistSlot> findByStatus(SlotDisplayStatus status);
}
