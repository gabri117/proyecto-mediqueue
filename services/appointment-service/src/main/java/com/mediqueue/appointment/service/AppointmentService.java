package com.mediqueue.appointment.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.appointment.domain.Appointment;
import com.mediqueue.appointment.domain.AppointmentAudit;
import com.mediqueue.appointment.domain.AppointmentHold;
import com.mediqueue.appointment.domain.IdempotencyKey;
import com.mediqueue.appointment.domain.OutboxEvent;
import com.mediqueue.appointment.domain.enums.AppointmentStatus;
import com.mediqueue.appointment.domain.enums.HoldStatus;
import com.mediqueue.appointment.domain.enums.IdempotencyStatus;
import com.mediqueue.appointment.domain.enums.OutboxPublicationStatus;
import com.mediqueue.appointment.dto.AppointmentRequest;
import com.mediqueue.appointment.dto.AppointmentResponse;
import com.mediqueue.appointment.events.published.AppointmentCancelledEvent;
import com.mediqueue.appointment.events.published.AppointmentConfirmedEvent;
import com.mediqueue.appointment.events.published.AppointmentHeldEvent;
import com.mediqueue.appointment.exception.BusinessException;
import com.mediqueue.appointment.exception.IllegalStateTransitionException;
import com.mediqueue.appointment.repository.AppointmentAuditRepository;
import com.mediqueue.appointment.repository.AppointmentHoldRepository;
import com.mediqueue.appointment.repository.AppointmentRepository;
import com.mediqueue.appointment.repository.IdempotencyKeyRepository;
import com.mediqueue.appointment.repository.OutboxEventRepository;
import jakarta.persistence.EntityNotFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

/**
 * Core service encapsulating all appointment business logic.
 *
 * <p>Coordinates appointment creation (with idempotency and hold TTL),
 * confirmation, cancellation/compensation, and read operations.</p>
 *
 * @since 0.0.1
 */
@Service
public class AppointmentService {

    private static final Logger log = LoggerFactory.getLogger(AppointmentService.class);
    private static final String CREATE_OPERATION = "CREATE_APPOINTMENT";

    private final AppointmentRepository appointmentRepository;
    private final AppointmentHoldRepository holdRepository;
    private final AppointmentAuditRepository auditRepository;
    private final IdempotencyKeyRepository idempotencyKeyRepository;
    private final OutboxEventRepository outboxEventRepository;
    private final AppointmentStateMachine stateMachine;
    private final ObjectMapper objectMapper;
    private final int holdTtlMinutes;

    public AppointmentService(AppointmentRepository appointmentRepository,
                              AppointmentHoldRepository holdRepository,
                              AppointmentAuditRepository auditRepository,
                              IdempotencyKeyRepository idempotencyKeyRepository,
                              OutboxEventRepository outboxEventRepository,
                              AppointmentStateMachine stateMachine,
                              ObjectMapper objectMapper,
                              @Value("${mediqueue.hold.ttl-minutes:5}") int holdTtlMinutes) {
        this.appointmentRepository = appointmentRepository;
        this.holdRepository = holdRepository;
        this.auditRepository = auditRepository;
        this.idempotencyKeyRepository = idempotencyKeyRepository;
        this.outboxEventRepository = outboxEventRepository;
        this.stateMachine = stateMachine;
        this.objectMapper = objectMapper;
        this.holdTtlMinutes = holdTtlMinutes;
    }

    // =========================================================================
    // createAppointment
    // =========================================================================

    /**
     * Creates a new appointment with hold TTL and idempotency protection.
     *
     * @param request        the appointment creation request
     * @param idempotencyKey the client-supplied idempotency key
     * @return the created appointment
     * @throws BusinessException if the request is already processing or the slot is taken
     */
    @Transactional
    @SuppressWarnings("null")
    public AppointmentResponse createAppointment(AppointmentRequest request, String idempotencyKey) {
        // (a) Idempotency check
        var existing = idempotencyKeyRepository
                .findByOperationTypeAndIdempotencyKey(CREATE_OPERATION, idempotencyKey);

        if (existing.isPresent()) {
            IdempotencyKey key = existing.get();
            if (key.getStatus() == IdempotencyStatus.SUCCEEDED) {
                UUID savedId = UUID.fromString(key.getResponseReference());
                Appointment saved = appointmentRepository.findById(savedId)
                        .orElseThrow(() -> new EntityNotFoundException("Appointment not found: " + savedId));
                return toResponse(saved);
            }
            if (key.getStatus() == IdempotencyStatus.PROCESSING) {
                throw new BusinessException("Solicitud en proceso");
            }
        }

        // (b) Create idempotency key with PROCESSING
        IdempotencyKey idemKey = new IdempotencyKey();
        idemKey.setOperationType(CREATE_OPERATION);
        idemKey.setIdempotencyKey(idempotencyKey);
        idemKey.setRequestHash(computeHash(idempotencyKey));
        idemKey.setStatus(IdempotencyStatus.PROCESSING);
        idemKey.setExpiresAt(Instant.now().plus(24, ChronoUnit.HOURS));
        idempotencyKeyRepository.save(idemKey);

        // (c) Verify slot availability
        holdRepository.findBySlotIdAndHoldStatus(request.slotId(), HoldStatus.ACTIVE)
                .ifPresent(h -> {
                    throw new BusinessException("Slot no disponible: ya tiene una reserva activa");
                });

        // (d) Create appointment
        Appointment appointment = new Appointment();
        appointment.setPatientId(request.patientId());
        appointment.setDentistId(request.dentistId());
        appointment.setSlotId(request.slotId());
        appointment.setAppointmentDate(request.appointmentDate());
        appointment.setStartTime(request.startTime());
        appointment.setEndTime(request.endTime());
        appointment.setNotes(request.notes());
        appointment.setAppointmentStatus(AppointmentStatus.PENDING_PAYMENT);
        appointmentRepository.save(appointment);

        // (e) Create hold with TTL
        Instant holdExpiry = Instant.now().plus(holdTtlMinutes, ChronoUnit.MINUTES);

        AppointmentHold hold = new AppointmentHold();
        hold.setAppointment(appointment);
        hold.setSlotId(request.slotId());
        hold.setHoldStatus(HoldStatus.ACTIVE);
        hold.setExpiresAt(holdExpiry);
        holdRepository.save(hold);

        // (f) Audit trail
        AppointmentAudit audit = new AppointmentAudit();
        audit.setAppointmentId(appointment.getAppointmentId());
        audit.setPreviousStatus(null);
        audit.setNewStatus(AppointmentStatus.PENDING_PAYMENT);
        audit.setChangeReason("Cita creada");
        auditRepository.save(audit);

        // (g) Outbox event
        AppointmentHeldEvent event = new AppointmentHeldEvent(
                UUID.randomUUID().toString(),
                "APPOINTMENT_HELD",
                Instant.now().toString(),
                new AppointmentHeldEvent.AppointmentHeldPayload(
                        appointment.getAppointmentId(),
                        appointment.getPatientId(),
                        appointment.getDentistId(),
                        appointment.getSlotId(),
                        appointment.getAppointmentDate(),
                        appointment.getStartTime(),
                        appointment.getEndTime(),
                        holdExpiry,
                        null
                )
        );
        saveOutboxEvent("appointments-exchange", appointment.getAppointmentId(),
                "appointment.held", event);

        // (h) Mark idempotency as succeeded
        idemKey.setStatus(IdempotencyStatus.SUCCEEDED);
        idemKey.setResponseReference(appointment.getAppointmentId().toString());
        idempotencyKeyRepository.save(idemKey);

        // (i) Return response
        return toResponse(appointment);
    }

    // =========================================================================
    // confirmAppointment
    // =========================================================================

    /**
     * Confirms an appointment after successful payment.
     *
     * @param appointmentId the appointment to confirm
     * @throws EntityNotFoundException if the appointment does not exist
     */
    @Transactional
    public void confirmAppointment(UUID appointmentId) {
        Appointment appointment = findOrFail(appointmentId);

        try {
            stateMachine.validate(appointment.getAppointmentStatus(), AppointmentStatus.CONFIRMED);
        } catch (IllegalStateTransitionException ex) {
            log.warn("confirm_skipped appointmentId={} reason={}", appointmentId, ex.getMessage());
            return;
        }

        appointment.setAppointmentStatus(AppointmentStatus.CONFIRMED);
        appointmentRepository.save(appointment);

        holdRepository.findBySlotIdAndHoldStatus(appointment.getSlotId(), HoldStatus.ACTIVE)
                .ifPresent(hold -> {
                    hold.setHoldStatus(HoldStatus.CONSUMED);
                    hold.setReleasedAt(Instant.now());
                    holdRepository.save(hold);
                });

        saveAudit(appointmentId, AppointmentStatus.PENDING_PAYMENT,
                AppointmentStatus.CONFIRMED, "Pago confirmado");

        AppointmentConfirmedEvent event = new AppointmentConfirmedEvent(
                UUID.randomUUID().toString(),
                "APPOINTMENT_CONFIRMED",
                Instant.now().toString(),
                new AppointmentConfirmedEvent.AppointmentConfirmedPayload(
                        appointment.getAppointmentId(),
                        appointment.getPatientId(),
                        appointment.getDentistId(),
                        appointment.getAppointmentDate(),
                        appointment.getStartTime()
                )
        );
        saveOutboxEvent("appointments-exchange", appointmentId,
                "appointment.confirmed", event);
    }

    // =========================================================================
    // compensateAppointment
    // =========================================================================

    /**
     * Cancels an appointment as compensation for a failed payment.
     *
     * @param appointmentId the appointment to cancel
     * @throws EntityNotFoundException if the appointment does not exist
     */
    @Transactional
    public void compensateAppointment(UUID appointmentId) {
        Appointment appointment = findOrFail(appointmentId);

        try {
            stateMachine.validate(appointment.getAppointmentStatus(), AppointmentStatus.CANCELLED);
        } catch (IllegalStateTransitionException ex) {
            log.warn("compensate_skipped appointmentId={} reason={}", appointmentId, ex.getMessage());
            return;
        }

        appointment.setAppointmentStatus(AppointmentStatus.CANCELLED);
        appointmentRepository.save(appointment);

        holdRepository.findBySlotIdAndHoldStatus(appointment.getSlotId(), HoldStatus.ACTIVE)
                .ifPresent(hold -> {
                    hold.setHoldStatus(HoldStatus.RELEASED);
                    hold.setReleasedAt(Instant.now());
                    holdRepository.save(hold);
                });

        saveAudit(appointmentId, AppointmentStatus.PENDING_PAYMENT,
                AppointmentStatus.CANCELLED, "Pago fallido");

        AppointmentCancelledEvent event = new AppointmentCancelledEvent(
                UUID.randomUUID().toString(),
                "APPOINTMENT_CANCELLED",
                Instant.now().toString(),
                new AppointmentCancelledEvent.AppointmentCancelledPayload(
                        appointment.getAppointmentId(),
                        appointment.getPatientId(),
                        appointment.getDentistId(),
                        appointment.getAppointmentDate(),
                        appointment.getStartTime()
                )
        );
        saveOutboxEvent("appointments-exchange", appointmentId,
                "appointment.cancelled", event);
    }

    // =========================================================================
    // Read operations
    // =========================================================================

    /**
     * Finds an appointment by its unique identifier.
     *
     * @param appointmentId the appointment ID
     * @return the appointment response
     * @throws EntityNotFoundException if the appointment does not exist
     */
    public AppointmentResponse findById(UUID appointmentId) {
        return toResponse(findOrFail(appointmentId));
    }

    /**
     * Finds all appointments for a given patient.
     *
     * @param patientId the patient's unique identifier
     * @return list of appointment responses
     */
    public List<AppointmentResponse> findByPatientId(UUID patientId) {
        return appointmentRepository.findByPatientId(patientId).stream()
                .map(this::toResponse)
                .toList();
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    @SuppressWarnings("null")
    private Appointment findOrFail(UUID appointmentId) {
        return appointmentRepository.findById(appointmentId)
                .orElseThrow(() -> new EntityNotFoundException("Appointment not found: " + appointmentId));
    }

    private AppointmentResponse toResponse(Appointment a) {
        return new AppointmentResponse(
                a.getAppointmentId(),
                a.getPatientId(),
                a.getDentistId(),
                a.getSlotId(),
                a.getAppointmentDate(),
                a.getStartTime(),
                a.getEndTime(),
                a.getAppointmentStatus().name(),
                a.getNotes(),
                a.getCreatedAt()
        );
    }

    private void saveAudit(UUID appointmentId, AppointmentStatus previous,
                           AppointmentStatus newStatus, String reason) {
        AppointmentAudit audit = new AppointmentAudit();
        audit.setAppointmentId(appointmentId);
        audit.setPreviousStatus(previous);
        audit.setNewStatus(newStatus);
        audit.setChangeReason(reason);
        auditRepository.save(audit);
    }

    private void saveOutboxEvent(String aggregateType, UUID aggregateId,
                                 String eventType, Object eventPayload) {
        OutboxEvent outbox = new OutboxEvent();
        outbox.setAggregateType(aggregateType);
        outbox.setAggregateId(aggregateId);
        outbox.setEventType(eventType);
        outbox.setPublicationStatus(OutboxPublicationStatus.PENDING);

        try {
            outbox.setPayload(objectMapper.writeValueAsString(eventPayload));
        } catch (Exception ex) {
            throw new RuntimeException("Failed to serialize outbox event payload", ex);
        }

        outboxEventRepository.save(outbox);
    }

    /**
     * Computes a SHA-256 hex digest of the given input string.
     * Falls back to returning the raw input if SHA-256 is unavailable.
     *
     * @param input the string to hash
     * @return hex-encoded SHA-256 digest, or {@code input} on failure
     */
    private String computeHash(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                hexString.append(String.format("%02x", b));
            }
            return hexString.toString();
        } catch (NoSuchAlgorithmException e) {
            log.warn("SHA-256 no disponible, usando fallback");
            return input;
        }
    }
}
