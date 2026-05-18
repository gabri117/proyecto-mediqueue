package com.mediqueue.payment.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.mediqueue.payment.domain.Payment;
import com.mediqueue.payment.domain.PaymentEventsOutbox;
import com.mediqueue.payment.domain.PaymentIdempotency;
import com.mediqueue.payment.domain.enums.IdempotencyStatus;
import com.mediqueue.payment.domain.enums.PaymentStatus;
import com.mediqueue.payment.dto.PaymentRequest;
import com.mediqueue.payment.events.consumed.AppointmentHeldEvent;
import com.mediqueue.payment.exception.ConflictException;
import com.mediqueue.payment.repository.PaymentEventsOutboxRepository;
import com.mediqueue.payment.repository.PaymentIdempotencyRepository;
import com.mediqueue.payment.repository.PaymentRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PaymentServiceTest {

    private final Map<UUID, Payment> payments = new ConcurrentHashMap<>();
    private final Map<String, PaymentIdempotency> idempotencies = new ConcurrentHashMap<>();
    private final List<PaymentEventsOutbox> outbox = new ArrayList<>();

    private PaymentRepository paymentRepository;
    private PaymentIdempotencyRepository idempotencyRepository;
    private PaymentEventsOutboxRepository outboxRepository;
    private PaymentSimulator simulator;
    private PaymentService paymentService;

    @BeforeEach
    void setUp() {
        paymentRepository = mock(PaymentRepository.class);
        idempotencyRepository = mock(PaymentIdempotencyRepository.class);
        outboxRepository = mock(PaymentEventsOutboxRepository.class);
        simulator = mock(PaymentSimulator.class);
        TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(new SimpleTransactionStatus());
        });

        when(paymentRepository.saveAndFlush(any(Payment.class))).thenAnswer(invocation -> savePayment(invocation.getArgument(0)));
        when(paymentRepository.save(any(Payment.class))).thenAnswer(invocation -> savePayment(invocation.getArgument(0)));
        when(paymentRepository.findById(any(UUID.class))).thenAnswer(invocation -> Optional.ofNullable(payments.get(invocation.getArgument(0))));
        when(paymentRepository.existsByAppointmentIdAndPaymentStatus(any(UUID.class), any(PaymentStatus.class))).thenAnswer(invocation -> {
            UUID appointmentId = invocation.getArgument(0);
            PaymentStatus status = invocation.getArgument(1);
            return payments.values().stream().anyMatch(payment ->
                    appointmentId.equals(payment.getAppointmentId()) && status == payment.getPaymentStatus());
        });
        when(paymentRepository.findAllByAppointmentIdOrderByRequestedAtDesc(any(UUID.class))).thenAnswer(invocation -> {
            UUID appointmentId = invocation.getArgument(0);
            return payments.values().stream()
                    .filter(payment -> appointmentId.equals(payment.getAppointmentId()))
                    .sorted(Comparator.comparing(Payment::getRequestedAt).reversed())
                    .toList();
        });
        when(paymentRepository.findAll(any(Pageable.class))).thenAnswer(invocation -> {
            Pageable pageable = invocation.getArgument(0);
            return new PageImpl<>(List.of(), pageable, 0);
        });
        when(paymentRepository.findByAppointmentId(any(UUID.class), any(Pageable.class))).thenAnswer(invocation -> {
            Pageable pageable = invocation.getArgument(1);
            return new PageImpl<>(List.of(), pageable, 0);
        });
        when(paymentRepository.findByPaymentStatus(any(PaymentStatus.class), any(Pageable.class))).thenAnswer(invocation -> {
            Pageable pageable = invocation.getArgument(1);
            return new PageImpl<>(List.of(), pageable, 0);
        });
        when(paymentRepository.findByAppointmentIdAndPaymentStatus(any(UUID.class), any(PaymentStatus.class), any(Pageable.class)))
                .thenAnswer(invocation -> {
                    Pageable pageable = invocation.getArgument(2);
                    return new PageImpl<>(List.of(), pageable, 0);
                });

        when(idempotencyRepository.findByIdempotencyKeyForUpdate(anyString()))
                .thenAnswer(invocation -> Optional.ofNullable(idempotencies.get(invocation.getArgument(0))));
        when(idempotencyRepository.saveAndFlush(any(PaymentIdempotency.class)))
                .thenAnswer(invocation -> saveIdempotency(invocation.getArgument(0)));
        when(idempotencyRepository.save(any(PaymentIdempotency.class)))
                .thenAnswer(invocation -> saveIdempotency(invocation.getArgument(0)));

        when(outboxRepository.save(any(PaymentEventsOutbox.class))).thenAnswer(invocation -> {
            PaymentEventsOutbox event = invocation.getArgument(0);
            if (event.getEventId() == null) {
                event.setEventId(UUID.randomUUID());
            }
            outbox.add(event);
            return event;
        });

        ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
        paymentService = new PaymentService(
                paymentRepository,
                idempotencyRepository,
                outboxRepository,
                new PaymentHashService(),
                simulator,
                transactionTemplate,
                objectMapper,
                new SimpleMeterRegistry(),
                1,
                24);
    }

    @Test
    void sameIdempotencyKeyAndBodyDoesNotCreateTwoPayments() {
        when(simulator.simulate(any())).thenReturn(PaymentStatus.APPROVED);
        PaymentRequest request = request(UUID.randomUUID(), BigDecimal.TEN);

        assertThat(paymentService.processManualPayment("same-key", request).httpStatus()).isEqualTo(HttpStatus.CREATED);
        assertThat(paymentService.processManualPayment("same-key", request).httpStatus()).isEqualTo(HttpStatus.OK);

        assertThat(payments).hasSize(1);
    }

    @Test
    void sameIdempotencyKeyWithDifferentBodyReturnsConflict() {
        when(simulator.simulate(any())).thenReturn(PaymentStatus.REJECTED);
        UUID appointmentId = UUID.randomUUID();

        paymentService.processManualPayment("same-key", request(appointmentId, BigDecimal.TEN));

        assertThatThrownBy(() -> paymentService.processManualPayment("same-key", request(appointmentId, BigDecimal.valueOf(20))))
                .isInstanceOf(ConflictException.class);
    }

    @Test
    void parallelRequestsForSameAppointmentDoNotLeaveTwoApprovedPayments() throws Exception {
        UUID appointmentId = UUID.randomUUID();
        when(simulator.simulate(any())).thenReturn(PaymentStatus.APPROVED);
        CountDownLatch start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(2);

        var first = executor.submit(() -> {
            start.await();
            return paymentService.processManualPayment("key-1", request(appointmentId, BigDecimal.TEN));
        });
        var second = executor.submit(() -> {
            start.await();
            return paymentService.processManualPayment("key-2", request(appointmentId, BigDecimal.TEN));
        });
        start.countDown();
        first.get();
        try {
            second.get();
        } catch (Exception ignored) {
            // A 409 is also acceptable for the loser of the approval race.
        }
        executor.shutdown();

        long approved = payments.values().stream()
                .filter(payment -> payment.getPaymentStatus() == PaymentStatus.APPROVED)
                .count();
        assertThat(approved).isLessThanOrEqualTo(1);
    }

    @Test
    void timeoutMarksPaymentTimeoutAndCreatesPaymentFailedOutbox() {
        when(simulator.simulate(any())).thenAnswer(invocation -> {
            Thread.sleep(1500);
            return PaymentStatus.APPROVED;
        });

        var result = paymentService.processManualPayment("timeout-key", request(UUID.randomUUID(), BigDecimal.TEN));

        assertThat(result.response().paymentStatus()).isEqualTo("TIMEOUT");
        assertThat(outbox).singleElement().satisfies(event -> assertThat(event.getEventType()).isEqualTo("PAYMENT_FAILED"));
    }

    @Test
    void rejectedPaymentCreatesPaymentFailedOutbox() {
        when(simulator.simulate(any())).thenReturn(PaymentStatus.REJECTED);

        var result = paymentService.processManualPayment("rejected-key", request(UUID.randomUUID(), BigDecimal.TEN));

        assertThat(result.response().paymentStatus()).isEqualTo("REJECTED");
        assertThat(outbox).singleElement().satisfies(event -> assertThat(event.getEventType()).isEqualTo("PAYMENT_FAILED"));
    }

    @Test
    void approvedPaymentCreatesPaymentSucceededOutbox() {
        when(simulator.simulate(any())).thenReturn(PaymentStatus.APPROVED);

        var result = paymentService.processManualPayment("approved-key", request(UUID.randomUUID(), BigDecimal.TEN));

        assertThat(result.response().paymentStatus()).isEqualTo("APPROVED");
        assertThat(outbox).singleElement().satisfies(event -> assertThat(event.getEventType()).isEqualTo("PAYMENT_SUCCEEDED"));
    }

    @Test
    void consumingSameAppointmentHeldEventTwiceCreatesOnlyOnePayment() {
        when(simulator.simulate(any())).thenReturn(PaymentStatus.APPROVED);
        AppointmentHeldEvent event = appointmentHeldEvent(UUID.randomUUID());

        paymentService.processAppointmentHeld(event);
        paymentService.processAppointmentHeld(event);

        assertThat(payments).hasSize(1);
    }

    @Test
    void getPaymentsNormalizesNegativePageAndCapsLargeSize() {
        var response = paymentService.getPayments(null, null, -1, 1000);

        assertThat(response.page()).isZero();
        assertThat(response.size()).isEqualTo(100);
    }

    private PaymentRequest request(UUID appointmentId, BigDecimal amount) {
        return new PaymentRequest(appointmentId, UUID.randomUUID(), amount, "GTQ");
    }

    private AppointmentHeldEvent appointmentHeldEvent(UUID appointmentId) {
        return new AppointmentHeldEvent(
                UUID.randomUUID(),
                "APPOINTMENT_HELD",
                Instant.now(),
                new AppointmentHeldEvent.Payload(
                        appointmentId,
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        null,
                        null,
                        null,
                        Instant.now().plusSeconds(300),
                        BigDecimal.valueOf(150)));
    }

    private synchronized Payment savePayment(Payment payment) {
        if (payment.getPaymentId() == null) {
            payment.setPaymentId(UUID.randomUUID());
        }
        if (payment.getPaymentStatus() == PaymentStatus.APPROVED) {
            boolean approvedExists = payments.values().stream().anyMatch(existing ->
                    !existing.getPaymentId().equals(payment.getPaymentId())
                            && existing.getAppointmentId().equals(payment.getAppointmentId())
                            && existing.getPaymentStatus() == PaymentStatus.APPROVED);
            if (approvedExists) {
                throw new DataIntegrityViolationException("uq_payments_appointment_approved");
            }
        }
        payments.put(payment.getPaymentId(), payment);
        return payment;
    }

    private PaymentIdempotency saveIdempotency(PaymentIdempotency idempotency) {
        if (idempotency.getPaymentIdempotencyId() == null) {
            idempotency.setPaymentIdempotencyId(UUID.randomUUID());
        }
        idempotencies.put(idempotency.getIdempotencyKey(), idempotency);
        return idempotency;
    }
}
