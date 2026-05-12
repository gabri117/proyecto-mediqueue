package com.mediqueue.payment.service;

import com.mediqueue.payment.dto.PaymentRequest;
import com.mediqueue.payment.events.consumed.AppointmentHeldEvent;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.springframework.stereotype.Service;

@Service
public class PaymentHashService {

    public String hashManualRequest(PaymentRequest request) {
        String raw = String.join("|",
                request.appointmentId().toString(),
                request.patientId().toString(),
                request.amount().stripTrailingZeros().toPlainString(),
                request.normalizedCurrency());
        return sha256(raw);
    }

    public String hashAppointmentHeld(AppointmentHeldEvent event) {
        AppointmentHeldEvent.Payload payload = event.payload();
        String raw = String.join("|",
                payload.appointmentId().toString(),
                payload.patientId().toString(),
                payload.amount().stripTrailingZeros().toPlainString(),
                event.eventType());
        return sha256(raw);
    }

    private String sha256(String raw) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(raw.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 is not available", ex);
        }
    }
}
