package com.mediqueue.notification.service;

public class NonRetryableNotificationException extends RuntimeException {

    public NonRetryableNotificationException(String message) {
        super(message);
    }
}
