package com.mediqueue.notification.repository;

import com.mediqueue.notification.domain.Notification;
import com.mediqueue.notification.domain.NotificationStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface NotificationRepository extends JpaRepository<Notification, UUID>, JpaSpecificationExecutor<Notification> {

    Page<Notification> findByPatientId(UUID patientId, Pageable pageable);

    Page<Notification> findByNotificationStatus(NotificationStatus status, Pageable pageable);

    Page<Notification> findByAppointmentId(UUID appointmentId, Pageable pageable);

    List<Notification> findByAppointmentId(UUID appointmentId);

    Optional<Notification> findByEventKey(String eventKey);

    boolean existsByEventKey(String eventKey);
}
