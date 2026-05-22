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
import com.mediqueue.appointment.exception.ServiceCapacityException;
import com.mediqueue.appointment.repository.AppointmentAuditRepository;
import com.mediqueue.appointment.repository.AppointmentHoldRepository;
import com.mediqueue.appointment.repository.AppointmentRepository;
import com.mediqueue.appointment.repository.IdempotencyKeyRepository;
import com.mediqueue.appointment.repository.OutboxEventRepository;
import jakarta.persistence.EntityNotFoundException;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

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
    private final PatientValidationService patientValidationService;
    private final SlotValidationService slotValidationService;
    private final TransactionTemplate transactionTemplate;
    private final JdbcTemplate jdbcTemplate;
    private final Map<String, Timer> createStageTimers;
    private final int holdTtlMinutes;
    private final long createTimingSlowThresholdMs;
    private final boolean createTimingLogEnabled;
    private final Semaphore createSemaphore;
    private final long createCapacityWaitMs;
    private final boolean jdbcFastPathEnabled;

    public AppointmentService(AppointmentRepository appointmentRepository,
                              AppointmentHoldRepository holdRepository,
                              AppointmentAuditRepository auditRepository,
                              IdempotencyKeyRepository idempotencyKeyRepository,
                              OutboxEventRepository outboxEventRepository,
                              AppointmentStateMachine stateMachine,
                              ObjectMapper objectMapper,
                              PatientValidationService patientValidationService,
                              SlotValidationService slotValidationService,
                              TransactionTemplate transactionTemplate,
                              JdbcTemplate jdbcTemplate,
                              MeterRegistry meterRegistry,
                              @Value("${mediqueue.hold.ttl-minutes:5}") int holdTtlMinutes,
                              @Value("${mediqueue.create.slow-threshold-ms:10000}") long createTimingSlowThresholdMs,
                              @Value("${mediqueue.create.timing-log-enabled:false}") boolean createTimingLogEnabled,
                              @Value("${mediqueue.create.max-concurrent:0}") int createMaxConcurrent,
                              @Value("${mediqueue.create.capacity-wait-ms:0}") long createCapacityWaitMs,
                              @Value("${mediqueue.create.jdbc-fast-path-enabled:false}") boolean jdbcFastPathEnabled) {
        this.appointmentRepository = appointmentRepository;
        this.holdRepository = holdRepository;
        this.auditRepository = auditRepository;
        this.idempotencyKeyRepository = idempotencyKeyRepository;
        this.outboxEventRepository = outboxEventRepository;
        this.stateMachine = stateMachine;
        this.objectMapper = objectMapper;
        this.patientValidationService = patientValidationService;
        this.slotValidationService = slotValidationService;
        this.transactionTemplate = transactionTemplate;
        this.jdbcTemplate = jdbcTemplate;
        this.createStageTimers = buildCreateStageTimers(meterRegistry);
        this.holdTtlMinutes = holdTtlMinutes;
        this.createTimingSlowThresholdMs = createTimingSlowThresholdMs;
        this.createTimingLogEnabled = createTimingLogEnabled;
        this.createSemaphore = createMaxConcurrent > 0 ? new Semaphore(createMaxConcurrent) : null;
        this.createCapacityWaitMs = Math.max(0, createCapacityWaitMs);
        this.jdbcFastPathEnabled = jdbcFastPathEnabled;
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
    @SuppressWarnings("null")
    public AppointmentResponse createAppointment(AppointmentRequest request, String idempotencyKey) {
        boolean capacityAcquired = acquireCreateCapacity();
        long requestStart = System.nanoTime();
        CreateAppointmentTiming timing = new CreateAppointmentTiming();

        try {
            // Keep external validation outside the database transaction so slow
            // downstream services do not pin scarce PostgreSQL connections.
            long stageStart = System.nanoTime();
            patientValidationService.validatePatientExists(request.patientId());
            recordCreateStage("patient_validation_ms", stageStart, timing);

            stageStart = System.nanoTime();
            slotValidationService.validateSlotExists(request.slotId());
            recordCreateStage("schedule_slot_validation_ms", stageStart, timing);

            AppointmentResponse response = transactionTemplate.execute(status -> {
                if (jdbcFastPathEnabled) {
                    return createAppointmentWithJdbcFastPath(request, idempotencyKey, requestStart, timing);
                }
                return createAppointmentInTransaction(request, idempotencyKey, requestStart, timing);
            });
            if (response == null) {
                throw new IllegalStateException("Appointment creation transaction returned no response");
            }
            return response;
        } finally {
            if (capacityAcquired) {
                createSemaphore.release();
            }
        }
    }

    @SuppressWarnings("null")
    private AppointmentResponse createAppointmentInTransaction(AppointmentRequest request,
                                                              String idempotencyKey,
                                                              long requestStart,
                                                              CreateAppointmentTiming timing) {
        // (a) Idempotency check
        long stageStart = System.nanoTime();
        var existing = idempotencyKeyRepository
                .findByOperationTypeAndIdempotencyKey(CREATE_OPERATION, idempotencyKey);
        recordCreateStage("idempotency_lookup_ms", stageStart, timing);

        if (existing.isPresent()) {
            IdempotencyKey key = existing.get();
            if (key.getStatus() == IdempotencyStatus.SUCCEEDED) {
                UUID savedId = UUID.fromString(key.getResponseReference());
                Appointment saved = appointmentRepository.findById(savedId)
                        .orElseThrow(() -> new EntityNotFoundException("Appointment not found: " + savedId));
                stageStart = System.nanoTime();
                AppointmentResponse response = toResponse(saved);
                recordCreateStage("response_mapping_ms", stageStart, timing);
                recordCreateStage("total_create_appointment_ms", requestStart, timing);
                logCreateTimingIfNeeded(saved, request, timing);
                return response;
            }
            if (key.getStatus() == IdempotencyStatus.PROCESSING) {
                throw new BusinessException("Solicitud en proceso");
            }
        }

        // (b) Create idempotency key with PROCESSING
        stageStart = System.nanoTime();
        IdempotencyKey idemKey = new IdempotencyKey();
        idemKey.setOperationType(CREATE_OPERATION);
        idemKey.setIdempotencyKey(idempotencyKey);
        idemKey.setRequestHash(computeHash(idempotencyKey));
        idemKey.setStatus(IdempotencyStatus.PROCESSING);
        idemKey.setExpiresAt(Instant.now().plus(24, ChronoUnit.HOURS));
        idempotencyKeyRepository.save(idemKey);
        recordCreateStage("idempotency_processing_save_ms", stageStart, timing);

        // (c) Verify slot availability
        stageStart = System.nanoTime();
        holdRepository.findBySlotIdAndHoldStatus(request.slotId(), HoldStatus.ACTIVE)
                .ifPresent(h -> {
                    throw new BusinessException("Slot no disponible: ya tiene una reserva activa");
                });
        recordCreateStage("slot_hold_or_lock_ms", stageStart, timing);

        // (d) Create appointment
        stageStart = System.nanoTime();
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
        recordCreateStage("appointment_save_ms", stageStart, timing);

        // (e) Create hold with TTL
        stageStart = System.nanoTime();
        Instant holdExpiry = Instant.now().plus(holdTtlMinutes, ChronoUnit.MINUTES);

        AppointmentHold hold = new AppointmentHold();
        hold.setAppointment(appointment);
        hold.setSlotId(request.slotId());
        hold.setHoldStatus(HoldStatus.ACTIVE);
        hold.setExpiresAt(holdExpiry);
        holdRepository.save(hold);
        recordCreateStage("hold_save_ms", stageStart, timing);

        // (f) Audit trail
        stageStart = System.nanoTime();
        AppointmentAudit audit = new AppointmentAudit();
        audit.setAppointmentId(appointment.getAppointmentId());
        audit.setPreviousStatus(null);
        audit.setNewStatus(AppointmentStatus.PENDING_PAYMENT);
        audit.setChangeReason("Cita creada");
        auditRepository.save(audit);
        recordCreateStage("audit_save_ms", stageStart, timing);

        // (g) Outbox event
        stageStart = System.nanoTime();
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
                        request.amount()
                )
        );
        saveOutboxEvent("appointments-exchange", appointment.getAppointmentId(),
                "appointment.held", event);
        recordCreateStage("outbox_save_ms", stageStart, timing);

        // (h) Mark idempotency as succeeded
        stageStart = System.nanoTime();
        idemKey.setStatus(IdempotencyStatus.SUCCEEDED);
        idemKey.setResponseReference(appointment.getAppointmentId().toString());
        idempotencyKeyRepository.save(idemKey);
        recordCreateStage("idempotency_success_save_ms", stageStart, timing);

        // (i) Return response
        stageStart = System.nanoTime();
        AppointmentResponse response = toResponse(appointment);
        recordCreateStage("response_mapping_ms", stageStart, timing);
        recordCreateStage("total_create_appointment_ms", requestStart, timing);
        logCreateTimingIfNeeded(appointment, request, timing);
        return response;
    }

    private AppointmentResponse createAppointmentWithJdbcFastPath(AppointmentRequest request,
                                                                  String idempotencyKey,
                                                                  long requestStart,
                                                                  CreateAppointmentTiming timing) {
        long stageStart = System.nanoTime();
        IdempotencySnapshot existing = findIdempotencySnapshot(idempotencyKey);
        recordCreateStage("idempotency_lookup_ms", stageStart, timing);

        if (existing != null) {
            if (existing.status() == IdempotencyStatus.SUCCEEDED && existing.responseReference() != null) {
                stageStart = System.nanoTime();
                AppointmentResponse response = findAppointmentResponse(UUID.fromString(existing.responseReference()));
                recordCreateStage("response_mapping_ms", stageStart, timing);
                recordCreateStage("total_create_appointment_ms", requestStart, timing);
                logCreateTimingIfNeeded(response, request, timing);
                return response;
            }
            if (existing.status() == IdempotencyStatus.PROCESSING) {
                throw new BusinessException("Solicitud en proceso");
            }
        }

        UUID appointmentId = UUID.randomUUID();
        UUID holdId = UUID.randomUUID();
        UUID auditId = UUID.randomUUID();
        UUID outboxId = UUID.randomUUID();
        UUID idemId = UUID.randomUUID();
        Instant now = Instant.now();
        Instant holdExpiry = now.plus(holdTtlMinutes, ChronoUnit.MINUTES);
        Instant idempotencyExpiry = now.plus(24, ChronoUnit.HOURS);

        stageStart = System.nanoTime();
        jdbcTemplate.update("""
                INSERT INTO idempotency_keys (
                    idempotency_id, operation_type, idempotency_key, request_hash,
                    status, created_at, expires_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                idemId, CREATE_OPERATION, idempotencyKey, computeHash(idempotencyKey),
                IdempotencyStatus.PROCESSING.name(), Timestamp.from(now), Timestamp.from(idempotencyExpiry));
        recordCreateStage("idempotency_processing_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        Boolean holdExists = jdbcTemplate.queryForObject("""
                SELECT EXISTS (
                    SELECT 1
                    FROM appointment_holds
                    WHERE slot_id = ?
                      AND hold_status = ?
                )
                """, Boolean.class, request.slotId(), HoldStatus.ACTIVE.name());
        if (Boolean.TRUE.equals(holdExists)) {
            throw new BusinessException("Slot no disponible: ya tiene una reserva activa");
        }
        recordCreateStage("slot_hold_or_lock_ms", stageStart, timing);

        stageStart = System.nanoTime();
        jdbcTemplate.update("""
                INSERT INTO appointments (
                    appointment_id, patient_id, dentist_id, slot_id, appointment_date,
                    start_time, end_time, appointment_status, notes, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                appointmentId, request.patientId(), request.dentistId(), request.slotId(),
                request.appointmentDate(), request.startTime(), request.endTime(),
                AppointmentStatus.PENDING_PAYMENT.name(), request.notes(),
                Timestamp.from(now), Timestamp.from(now));
        recordCreateStage("appointment_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        jdbcTemplate.update("""
                INSERT INTO appointment_holds (
                    hold_id, appointment_id, slot_id, hold_status, expires_at, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                holdId, appointmentId, request.slotId(), HoldStatus.ACTIVE.name(),
                Timestamp.from(holdExpiry), Timestamp.from(now));
        recordCreateStage("hold_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        jdbcTemplate.update("""
                INSERT INTO appointment_audit (
                    audit_id, appointment_id, previous_status, new_status, change_reason, changed_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                auditId, appointmentId, null, AppointmentStatus.PENDING_PAYMENT.name(),
                "Cita creada", Timestamp.from(now));
        recordCreateStage("audit_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        AppointmentHeldEvent event = new AppointmentHeldEvent(
                UUID.randomUUID().toString(),
                "APPOINTMENT_HELD",
                now.toString(),
                new AppointmentHeldEvent.AppointmentHeldPayload(
                        appointmentId,
                        request.patientId(),
                        request.dentistId(),
                        request.slotId(),
                        request.appointmentDate(),
                        request.startTime(),
                        request.endTime(),
                        holdExpiry,
                        request.amount()
                )
        );
        jdbcTemplate.update("""
                INSERT INTO outbox_events (
                    event_id, aggregate_type, aggregate_id, event_type, payload,
                    publication_status, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                outboxId, "appointments-exchange", appointmentId, "appointment.held",
                serializeEventPayload(event), OutboxPublicationStatus.PENDING.name(), Timestamp.from(now));
        recordCreateStage("outbox_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        jdbcTemplate.update("""
                UPDATE idempotency_keys
                SET status = ?, response_reference = ?
                WHERE idempotency_id = ?
                """,
                IdempotencyStatus.SUCCEEDED.name(), appointmentId.toString(), idemId);
        recordCreateStage("idempotency_success_save_ms", stageStart, timing);

        stageStart = System.nanoTime();
        AppointmentResponse response = new AppointmentResponse(
                appointmentId,
                request.patientId(),
                request.dentistId(),
                request.slotId(),
                request.appointmentDate(),
                request.startTime(),
                request.endTime(),
                AppointmentStatus.PENDING_PAYMENT.name(),
                request.notes(),
                now
        );
        recordCreateStage("response_mapping_ms", stageStart, timing);
        recordCreateStage("total_create_appointment_ms", requestStart, timing);
        logCreateTimingIfNeeded(response, request, timing);
        return response;
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
            if (appointment.getAppointmentStatus() == AppointmentStatus.CONFIRMED) {
                log.debug("confirm_duplicate_skipped appointmentId={}", appointmentId);
            } else {
                log.warn("confirm_skipped appointmentId={} reason={}", appointmentId, ex.getMessage());
            }
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
                        appointment.getSlotId(),
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
            if (appointment.getAppointmentStatus() == AppointmentStatus.CANCELLED) {
                log.debug("compensate_duplicate_skipped appointmentId={}", appointmentId);
            } else {
                log.warn("compensate_skipped appointmentId={} reason={}", appointmentId, ex.getMessage());
            }
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
                        appointment.getSlotId(),
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

    private IdempotencySnapshot findIdempotencySnapshot(String idempotencyKey) {
        List<IdempotencySnapshot> matches = jdbcTemplate.query("""
                SELECT status, response_reference
                FROM idempotency_keys
                WHERE operation_type = ?
                  AND idempotency_key = ?
                LIMIT 1
                """,
                (rs, rowNum) -> new IdempotencySnapshot(
                        IdempotencyStatus.valueOf(rs.getString("status")),
                        rs.getString("response_reference")),
                CREATE_OPERATION, idempotencyKey);
        return matches.isEmpty() ? null : matches.getFirst();
    }

    private AppointmentResponse findAppointmentResponse(UUID appointmentId) {
        return jdbcTemplate.queryForObject("""
                SELECT appointment_id, patient_id, dentist_id, slot_id, appointment_date,
                       start_time, end_time, appointment_status, notes, created_at
                FROM appointments
                WHERE appointment_id = ?
                """, this::mapAppointmentResponse, appointmentId);
    }

    private AppointmentResponse mapAppointmentResponse(ResultSet rs, int rowNum) throws SQLException {
        Timestamp createdAt = rs.getTimestamp("created_at");
        return new AppointmentResponse(
                rs.getObject("appointment_id", UUID.class),
                rs.getObject("patient_id", UUID.class),
                rs.getObject("dentist_id", UUID.class),
                rs.getObject("slot_id", UUID.class),
                rs.getObject("appointment_date", LocalDate.class),
                rs.getObject("start_time", LocalTime.class),
                rs.getObject("end_time", LocalTime.class),
                rs.getString("appointment_status"),
                rs.getString("notes"),
                createdAt != null ? createdAt.toInstant() : null
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

    private String serializeEventPayload(Object eventPayload) {
        try {
            return objectMapper.writeValueAsString(eventPayload);
        } catch (Exception ex) {
            throw new RuntimeException("Failed to serialize outbox event payload", ex);
        }
    }

    private void recordCreateStage(String stage, long startNanos, CreateAppointmentTiming timing) {
        long elapsedNanos = System.nanoTime() - startNanos;
        createStageTimers.get(stage).record(elapsedNanos, TimeUnit.NANOSECONDS);
        timing.record(stage, TimeUnit.NANOSECONDS.toMillis(elapsedNanos));
    }

    private boolean acquireCreateCapacity() {
        if (createSemaphore == null) {
            return false;
        }
        boolean acquired;
        try {
            acquired = createCapacityWaitMs > 0
                    ? createSemaphore.tryAcquire(createCapacityWaitMs, TimeUnit.MILLISECONDS)
                    : createSemaphore.tryAcquire();
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new ServiceCapacityException("Appointment create interrupted while waiting for capacity");
        }
        if (!acquired) {
            throw new ServiceCapacityException("Appointment create concurrency limit reached");
        }
        return true;
    }

    private Map<String, Timer> buildCreateStageTimers(MeterRegistry registry) {
        return Map.ofEntries(
                createStageTimer(registry, "patient_validation_ms"),
                createStageTimer(registry, "schedule_slot_validation_ms"),
                createStageTimer(registry, "idempotency_lookup_ms"),
                createStageTimer(registry, "idempotency_processing_save_ms"),
                createStageTimer(registry, "slot_hold_or_lock_ms"),
                createStageTimer(registry, "appointment_save_ms"),
                createStageTimer(registry, "hold_save_ms"),
                createStageTimer(registry, "audit_save_ms"),
                createStageTimer(registry, "outbox_save_ms"),
                createStageTimer(registry, "idempotency_success_save_ms"),
                createStageTimer(registry, "response_mapping_ms"),
                createStageTimer(registry, "total_create_appointment_ms")
        );
    }

    private Map.Entry<String, Timer> createStageTimer(MeterRegistry registry, String stage) {
        return Map.entry(stage, Timer.builder("mediqueue.appointment.create.stage.duration")
                .description("Appointment creation stage duration")
                .tag("stage", stage)
                .register(registry));
    }

    private void logCreateTimingIfNeeded(Appointment appointment,
                                         AppointmentRequest request,
                                         CreateAppointmentTiming timing) {
        long totalMs = timing.totalMs();
        if (createTimingLogEnabled || totalMs >= createTimingSlowThresholdMs) {
            log.info("appointment_create_timing appointmentId={} patientId={} dentistId={} slotId={} totalMs={} stages={}",
                    appointment.getAppointmentId(), request.patientId(), request.dentistId(), request.slotId(),
                    totalMs, timing.stageDurationsMs());
        }
    }

    private void logCreateTimingIfNeeded(AppointmentResponse appointment,
                                         AppointmentRequest request,
                                         CreateAppointmentTiming timing) {
        long totalMs = timing.totalMs();
        if (createTimingLogEnabled || totalMs >= createTimingSlowThresholdMs) {
            log.info("appointment_create_timing appointmentId={} patientId={} dentistId={} slotId={} totalMs={} stages={}",
                    appointment.appointmentId(),
                    request.patientId(),
                    request.dentistId(),
                    request.slotId(),
                    totalMs,
                    timing.stageDurationsMs());
        }
    }

    private record IdempotencySnapshot(IdempotencyStatus status, String responseReference) {
    }

    private static class CreateAppointmentTiming {
        private final Map<String, Long> stageDurationsMs = new LinkedHashMap<>();

        void record(String stage, long elapsedMs) {
            stageDurationsMs.put(stage, elapsedMs);
        }

        long totalMs() {
            return stageDurationsMs.getOrDefault("total_create_appointment_ms", 0L);
        }

        Map<String, Long> stageDurationsMs() {
            return stageDurationsMs;
        }
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
