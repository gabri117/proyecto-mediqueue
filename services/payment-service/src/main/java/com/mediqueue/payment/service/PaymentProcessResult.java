package com.mediqueue.payment.service;

import com.mediqueue.payment.dto.PaymentResponse;
import org.springframework.http.HttpStatus;

public record PaymentProcessResult(PaymentResponse response, HttpStatus httpStatus) {
}
