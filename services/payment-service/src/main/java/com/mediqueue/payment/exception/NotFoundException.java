package com.mediqueue.payment.exception;

import org.springframework.http.HttpStatus;

public class NotFoundException extends BusinessException {

    public NotFoundException(String message) {
        super("PAYMENT_NOT_FOUND", message, HttpStatus.NOT_FOUND);
    }
}
