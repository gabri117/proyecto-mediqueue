package com.mediqueue.payment.repository;

import com.mediqueue.payment.domain.Payment;
import com.mediqueue.payment.domain.enums.PaymentStatus;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PaymentRepository extends JpaRepository<Payment, UUID> {

    Optional<Payment> findByAppointmentId(UUID appointmentId);

    Page<Payment> findAll(Pageable pageable);

    Page<Payment> findByAppointmentId(UUID appointmentId, Pageable pageable);

    Page<Payment> findByPaymentStatus(PaymentStatus paymentStatus, Pageable pageable);

    Page<Payment> findByAppointmentIdAndPaymentStatus(UUID appointmentId, PaymentStatus paymentStatus, Pageable pageable);

    List<Payment> findAllByAppointmentIdOrderByRequestedAtDesc(UUID appointmentId);

    boolean existsByAppointmentIdAndPaymentStatus(UUID appointmentId, PaymentStatus status);

    Optional<Payment> findFirstByAppointmentIdAndPaymentStatus(UUID appointmentId, PaymentStatus status);
}
