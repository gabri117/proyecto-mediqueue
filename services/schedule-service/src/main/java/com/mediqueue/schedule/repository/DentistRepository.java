package com.mediqueue.schedule.repository;

import com.mediqueue.schedule.domain.Dentist;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface DentistRepository extends JpaRepository<Dentist, UUID> {

    Optional<Dentist> findByEmail(String email);
}
