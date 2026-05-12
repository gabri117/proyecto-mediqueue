package com.mediqueue.schedule.repository;

import com.mediqueue.schedule.domain.DentistWorkingHours;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface DentistWorkingHoursRepository extends JpaRepository<DentistWorkingHours, UUID> {

    List<DentistWorkingHours> findByDentistId(UUID dentistId);
}
