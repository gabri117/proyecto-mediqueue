package com.mediqueue.payment.exception;

import org.springframework.http.HttpStatus;

public class ConflictException extends BusinessException {

    public ConflictException(String message) {
        super("PAYMENT_CONFLICT", message, HttpStatus.CONFLICT);
    }
}
