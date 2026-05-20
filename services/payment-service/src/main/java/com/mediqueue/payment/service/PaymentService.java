package com.mediqueue.payment.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.payment.domain.Payment;
import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.PaymentIdempotency;
import com.mediqueue.payment.domain.enums.IdempotencyStatus;
import com.mediqueue.payment.domain.enums.PaymentStatus;
import com.mediqueue.payment.dto.PaymentRequest;
import com.mediqueue.payment.dto.PaymentResponse;
import com.mediqueue.payment.dto.PagedResponse;
import com.mediqueue.payment.events.BaseEvent;
import com.mediqueue.payment.events.consumed.AppointmentHeldEvent;
import com.mediqueue.payment.events.published.PaymentFailedEvent;
import com.mediqueue.payment.events.published.PaymentSucceededEvent;
import com.mediqueue.payment.exception.BusinessException;
import com.mediqueue.payment.exception.ConflictException;
import com.mediqueue.payment.exception.NotFoundException;
import com.mediqueue.payment.repository.PaymentEventsOutboxRepository;
import com.mediqueue.payment.repository.PaymentIdempotencyRepository;
import com.mediqueue.payment.repository.PaymentRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Slf4j
@Service
public class PaymentService {

    private static final String PAYMENT_SUCCEEDED = "PAYMENT_SUCCEEDED";
    private static final String PAYMENT_FAILED = "PAYMENT_FAILED";

    private final PaymentRepository paymentRepository;
    private final PaymentIdempotencyRepository idempotencyRepository;
    private final PaymentEventsOutboxRepository outboxRepository;
    private final PaymentHashService hashService;
    private final PaymentSimulator simulator;
    private final TransactionTemplate transactionTemplate;
    private final ObjectMapper objectMapper;
    private final long timeoutSeconds;
    private final long idempotencyTtlHours;
    private final Counter processedCounter;
    private final Counter approvedCounter;
    private final Counter rejectedCounter;
    private final Counter timeoutCounter;

    public PaymentService(
            PaymentRepository paymentRepository,
            PaymentIdempotencyRepository idempotencyRepository,
            PaymentEventsOutboxRepository outboxRepository,
            PaymentHashService hashService,
            PaymentSimulator simulator,
            TransactionTemplate transactionTemplate,
            ObjectMapper objectMapper,
            MeterRegistry meterRegistry,
            @Value("${mediqueue.payment.timeout-seconds:10}") long timeoutSeconds,
            @Value("${mediqueue.payment.idempotency-ttl-hours:24}") long idempotencyTtlHours) {
        this.paymentRepository = paymentRepository;
        this.idempotencyRepository = idempotencyRepository;
        this.outboxRepository = outboxRepository;
        this.hashService = hashService;
        this.simulator = simulator;
        this.transactionTemplate = transactionTemplate;
        this.objectMapper = objectMapper;
        this.timeoutSeconds = timeoutSeconds;
        this.idempotencyTtlHours = idempotencyTtlHours;
        this.processedCounter = meterRegistry.counter("payments.processed.total");
        this.approvedCounter = meterRegistry.counter("payments.approved.total");
        this.rejectedCounter = meterRegistry.counter("payments.rejected.total");
        this.timeoutCounter = meterRegistry.counter("payments.timeout.total");
    }

    public PaymentProcessResult processManualPayment(String idempotencyKey, PaymentRequest request) {
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw new BusinessException("PAYMENT_BAD_REQUEST", "X-Idempotency-Key is required");
        }
        String requestHash = hashService.hashManualRequest(request);
        PaymentCreation creation = createOrLoadPayment(idempotencyKey.trim(), requestHash, request);
        if (!creation.shouldProcess()) {
            return creation.result();
        }
        PaymentResponse response = simulateAndFinalize(creation.payment().getPaymentId(), creation.payment().getAmount(), idempotencyKey.trim(), true);
        return new PaymentProcessResult(response, HttpStatus.CREATED);
    }

    public void processAppointmentHeld(AppointmentHeldEvent event) {
        if (event == null || event.payload() == null || event.payload().appointmentId() == null) {
            log.warn("Invalid AppointmentHeld event received without appointment payload");
            return;
        }
        AppointmentHeldEvent.Payload payload = event.payload();
        try (MDC.MDCCloseable appointmentMdc = MDC.putCloseable("appointmentId", payload.appointmentId().toString())) {
            if (payload.amount() == null || payload.amount().signum() <= 0) {
                log.warn("Invalid AppointmentHeld amount; event will be acked without creating payment");
                return;
            }
            PaymentRequest request = new PaymentRequest(payload.appointmentId(), payload.patientId(), payload.amount(), "GTQ");
            String key = "appointment-held:" + payload.appointmentId();
            String requestHash = hashService.hashAppointmentHeld(event);
            PaymentCreation creation = createOrLoadPayment(key, requestHash, request);
            if (!creation.shouldProcess()) {
                log.info("AppointmentHeld event is idempotent or already processing");
                return;
            }
            simulateAndFinalize(creation.payment().getPaymentId(), creation.payment().getAmount(), key, false);
        }
    }

    public PaymentResponse getPayment(UUID paymentId) {
        return paymentRepository.findById(paymentId)
                .map(this::toResponse)
                .orElseThrow(() -> new NotFoundException("Payment not found: " + paymentId));
    }

    public List<PaymentResponse> getPaymentsByAppointment(UUID appointmentId) {
        return paymentRepository.findAllByAppointmentIdOrderByRequestedAtDesc(appointmentId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    public PagedResponse<PaymentResponse> getPayments(UUID appointmentId, PaymentStatus status, int page, int size) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.max(1, Math.min(size, 100));
        Pageable pageable = PageRequest.of(
                normalizedPage,
                normalizedSize,
                Sort.by(Sort.Direction.DESC, "requestedAt"));

        Page<Payment> payments;
        if (appointmentId != null && status != null) {
            payments = paymentRepository.findByAppointmentIdAndPaymentStatus(appointmentId, status, pageable);
        } else if (appointmentId != null) {
            payments = paymentRepository.findByAppointmentId(appointmentId, pageable);
        } else if (status != null) {
            payments = paymentRepository.findByPaymentStatus(status, pageable);
        } else {
            payments = paymentRepository.findAll(pageable);
        }

        Page<PaymentResponse> responses = payments.map(this::toResponse);
        return new PagedResponse<>(
                responses.getContent(),
                responses.getNumber(),
                responses.getSize(),
                responses.getTotalElements(),
                responses.getTotalPages(),
                responses.isFirst(),
                responses.isLast());
    }

    private PaymentCreation createOrLoadPayment(String idempotencyKey, String requestHash, PaymentRequest request) {
        try {
            return Objects.requireNonNull(transactionTemplate.execute(status -> {
                idempotencyRepository.findByIdempotencyKeyForUpdate(idempotencyKey).ifPresent(existing -> {
                    if (!existing.getRequestHash().equals(requestHash)) {
                        throw new ConflictException("Idempotency key was already used with a different request");
                    }
                });

                PaymentIdempotency existing = idempotencyRepository.findByIdempotencyKeyForUpdate(idempotencyKey).orElse(null);
                if (existing != null) {
                    return handleExistingIdempotency(existing);
                }
                if (paymentRepository.existsByAppointmentIdAndPaymentStatus(request.appointmentId(), PaymentStatus.APPROVED)) {
                    throw new ConflictException("Appointment already has an approved payment");
                }

                Payment payment = new Payment();
                payment.setAppointmentId(request.appointmentId());
                payment.setPatientId(request.patientId());
                payment.setAmount(request.amount());
                payment.setCurrency(request.normalizedCurrency());
                payment.setPaymentStatus(PaymentStatus.PENDING);
                payment.setRequestedAt(now());
                paymentRepository.saveAndFlush(payment);

                PaymentIdempotency idempotency = new PaymentIdempotency();
                idempotency.setIdempotencyKey(idempotencyKey);
                idempotency.setRequestHash(requestHash);
                idempotency.setPaymentId(payment.getPaymentId());
                idempotency.setStatus(IdempotencyStatus.PROCESSING);
                idempotency.setCreatedAt(now());
                idempotency.setExpiresAt(now().plusHours(idempotencyTtlHours));
                idempotencyRepository.saveAndFlush(idempotency);

                log.info("Payment processing started");
                return PaymentCreation.newPayment(payment);
            }));
        } catch (DataIntegrityViolationException ex) {
            log.warn("Idempotency race detected for key {}", idempotencyKey);
            return Objects.requireNonNull(transactionTemplate.execute(status -> idempotencyRepository
                    .findByIdempotencyKeyForUpdate(idempotencyKey)
                    .map(this::handleExistingIdempotency)
                    .orElseThrow(() -> ex)));
        }
    }

    private PaymentCreation handleExistingIdempotency(PaymentIdempotency existing) {
        if (existing.getPaymentId() == null) {
            log.warn("Idempotent request is already processing without a payment yet");
            return PaymentCreation.existing(null, HttpStatus.ACCEPTED);
        }
        Payment payment = paymentRepository.findById(existing.getPaymentId())
                .orElseThrow(() -> new NotFoundException("Payment not found for idempotency key"));
        HttpStatus status = existing.getStatus() == IdempotencyStatus.PROCESSING
                ? HttpStatus.ACCEPTED
                : HttpStatus.OK;
        log.info("Returning idempotent payment result with status {}", existing.getStatus());
        return PaymentCreation.existing(payment, status);
    }

    private PaymentResponse simulateAndFinalize(UUID paymentId, java.math.BigDecimal amount, String idempotencyKey, boolean throwConflictOnApprovedRace) {
        PaymentStatus simulatedStatus = simulateWithTimeout(amount);
        try (MDC.MDCCloseable paymentMdc = MDC.putCloseable("paymentId", paymentId.toString())) {
            try {
                return finalizePayment(paymentId, idempotencyKey, simulatedStatus);
            } catch (DataIntegrityViolationException ex) {
                log.warn("Approved payment race detected for payment {}", paymentId);
                PaymentResponse rejected = rejectAfterApprovedRace(paymentId, idempotencyKey);
                if (throwConflictOnApprovedRace) {
                    throw new ConflictException("Appointment already has an approved payment");
                }
                return rejected;
            }
        }
    }

    private PaymentStatus simulateWithTimeout(java.math.BigDecimal amount) {
        long startNanos = System.nanoTime();
        PaymentStatus status = simulator.simulate(amount);
        long elapsedSeconds = TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startNanos);
        if (elapsedSeconds > timeoutSeconds) {
            return PaymentStatus.TIMEOUT;
        }
        return status;
    }

    private PaymentResponse finalizePayment(UUID paymentId, String idempotencyKey, PaymentStatus simulatedStatus) {
        return Objects.requireNonNull(transactionTemplate.execute(status -> {
            Payment payment = paymentRepository.findById(paymentId)
                    .orElseThrow(() -> new NotFoundException("Payment not found: " + paymentId));
            PaymentIdempotency idempotency = idempotencyRepository.findByIdempotencyKeyForUpdate(idempotencyKey)
                    .orElseThrow(() -> new NotFoundException("Idempotency record not found"));

            PaymentStatus finalStatus = simulatedStatus;
            if (simulatedStatus == PaymentStatus.APPROVED
                    && paymentRepository.existsByAppointmentIdAndPaymentStatus(payment.getAppointmentId(), PaymentStatus.APPROVED)) {
                finalStatus = PaymentStatus.REJECTED;
                log.warn("Payment rejected because appointment already has an approved payment");
            }

            payment.setPaymentStatus(finalStatus);
            payment.setResolvedAt(now());
            paymentRepository.saveAndFlush(payment);
            outboxRepository.save(buildOutboxEvent(payment, finalStatus));

            idempotency.setStatus(IdempotencyStatus.SUCCEEDED);
            idempotency.setPaymentId(payment.getPaymentId());
            idempotencyRepository.save(idempotency);
            incrementCounters(finalStatus);
            log.info("Payment processing finished with status {}", finalStatus);
            return toResponse(payment);
        }));
    }

    private PaymentResponse rejectAfterApprovedRace(UUID paymentId, String idempotencyKey) {
        return Objects.requireNonNull(transactionTemplate.execute(status -> {
            Payment payment = paymentRepository.findById(paymentId)
                    .orElseThrow(() -> new NotFoundException("Payment not found: " + paymentId));
            payment.setPaymentStatus(PaymentStatus.REJECTED);
            payment.setResolvedAt(now());
            paymentRepository.saveAndFlush(payment);
            outboxRepository.save(buildOutboxEvent(payment, PaymentStatus.REJECTED));

            idempotencyRepository.findByIdempotencyKeyForUpdate(idempotencyKey).ifPresent(idempotency -> {
                idempotency.setStatus(IdempotencyStatus.SUCCEEDED);
                idempotency.setPaymentId(payment.getPaymentId());
                idempotencyRepository.save(idempotency);
            });
            incrementCounters(PaymentStatus.REJECTED);
            return toResponse(payment);
        }));
    }

    private PaymentEventsOutbox buildOutboxEvent(Payment payment, PaymentStatus status) {
        PaymentEventsOutbox outbox = new PaymentEventsOutbox();
        outbox.setPaymentId(payment.getPaymentId());
        outbox.setCreatedAt(now());
        if (status == PaymentStatus.APPROVED) {
            outbox.setEventType(PAYMENT_SUCCEEDED);
            outbox.setPayload(toJson(BaseEvent.of(PAYMENT_SUCCEEDED, new PaymentSucceededEvent(
                    payment.getPaymentId(),
                    payment.getAppointmentId(),
                    payment.getPatientId(),
                    payment.getAmount(),
                    toInstant(payment.getResolvedAt())))));
            return outbox;
        }
        String reason = status == PaymentStatus.TIMEOUT ? "TIMEOUT" : "REJECTED";
        outbox.setEventType(PAYMENT_FAILED);
        outbox.setPayload(toJson(BaseEvent.of(PAYMENT_FAILED, new PaymentFailedEvent(
                payment.getPaymentId(),
                payment.getAppointmentId(),
                payment.getPatientId(),
                reason,
                toInstant(payment.getResolvedAt())))));
        return outbox;
    }

    private String toJson(Object event) {
        try {
            return objectMapper.writeValueAsString(event);
        } catch (JsonProcessingException ex) {
            throw new BusinessException("PAYMENT_EVENT_SERIALIZATION_ERROR", "Could not serialize payment event");
        }
    }

    private void incrementCounters(PaymentStatus status) {
        processedCounter.increment();
        if (status == PaymentStatus.APPROVED) {
            approvedCounter.increment();
        } else if (status == PaymentStatus.TIMEOUT) {
            timeoutCounter.increment();
        } else {
            rejectedCounter.increment();
        }
    }

    private PaymentResponse toResponse(Payment payment) {
        if (payment == null) {
            return null;
        }
        return new PaymentResponse(
                payment.getPaymentId(),
                payment.getAppointmentId(),
                payment.getPatientId(),
                payment.getAmount(),
                payment.getCurrency(),
                payment.getPaymentStatus().name(),
                payment.getRequestedAt(),
                payment.getResolvedAt());
    }

    private LocalDateTime now() {
        return LocalDateTime.now(ZoneOffset.UTC);
    }

    private Instant toInstant(LocalDateTime value) {
        return value.toInstant(ZoneOffset.UTC);
    }

    private record PaymentCreation(Payment payment, boolean shouldProcess, PaymentProcessResult result) {

        static PaymentCreation newPayment(Payment payment) {
            return new PaymentCreation(payment, true, null);
        }

        static PaymentCreation existing(Payment payment, HttpStatus status) {
            return new PaymentCreation(payment, false, new PaymentProcessResult(
                    payment == null ? null : new PaymentServiceResponseMapper().map(payment),
                    status));
        }
    }

    private static class PaymentServiceResponseMapper {
        PaymentResponse map(Payment payment) {
            return new PaymentResponse(
                    payment.getPaymentId(),
                    payment.getAppointmentId(),
                    payment.getPatientId(),
                    payment.getAmount(),
                    payment.getCurrency(),
                    payment.getPaymentStatus().name(),
                    payment.getRequestedAt(),
                    payment.getResolvedAt());
        }
    }
}
