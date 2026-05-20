package com.mediqueue.payment.service;

import com.mediqueue.payment.domain.enums.PaymentStatus;
import java.util.concurrent.ThreadLocalRandom;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class PaymentSimulator {

    private final long minDelayMs;
    private final long maxDelayMs;
    private final double approvalRate;

    public PaymentSimulator(
            @Value("${mediqueue.payment.simulator.min-delay-ms:1000}") long minDelayMs,
            @Value("${mediqueue.payment.simulator.max-delay-ms:8000}") long maxDelayMs,
            @Value("${mediqueue.payment.simulator.approval-rate:0.80}") double approvalRate) {
        this.minDelayMs = Math.max(0, minDelayMs);
        this.maxDelayMs = Math.max(this.minDelayMs, maxDelayMs);
        this.approvalRate = Math.max(0.0, Math.min(1.0, approvalRate));
    }

    public PaymentStatus simulate(java.math.BigDecimal amount) {
        long delay = minDelayMs == maxDelayMs
                ? minDelayMs
                : ThreadLocalRandom.current().nextLong(minDelayMs, maxDelayMs + 1);
        try {
            Thread.sleep(delay);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("Payment simulation interrupted");
            return PaymentStatus.TIMEOUT;
        }
        return amount != null && ThreadLocalRandom.current().nextDouble() < approvalRate
                ? PaymentStatus.APPROVED
                : PaymentStatus.REJECTED;
    }
}
