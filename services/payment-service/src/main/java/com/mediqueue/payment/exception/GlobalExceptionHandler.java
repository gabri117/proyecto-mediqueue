package com.mediqueue.payment.exception;

import com.mediqueue.payment.dto.ErrorResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.ClientAbortException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + " " + error.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return error(HttpStatus.BAD_REQUEST, "PAYMENT_BAD_REQUEST", message);
    }

    @ExceptionHandler(MissingRequestHeaderException.class)
    ResponseEntity<ErrorResponse> handleMissingHeader(MissingRequestHeaderException ex) {
        return error(HttpStatus.BAD_REQUEST, "PAYMENT_BAD_REQUEST", "Missing required header: " + ex.getHeaderName());
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    ResponseEntity<ErrorResponse> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return error(HttpStatus.BAD_REQUEST, "PAYMENT_BAD_REQUEST", "Invalid parameter value");
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorResponse> handleUnreadableMessage(HttpMessageNotReadableException ex) {
        return error(HttpStatus.BAD_REQUEST, "PAYMENT_BAD_REQUEST", "Malformed request body");
    }

    @ExceptionHandler(ConflictException.class)
    ResponseEntity<ErrorResponse> handleConflict(ConflictException ex) {
        return error(HttpStatus.CONFLICT, ex.getCode(), ex.getMessage());
    }

    @ExceptionHandler(NotFoundException.class)
    ResponseEntity<ErrorResponse> handleNotFound(NotFoundException ex) {
        return error(HttpStatus.NOT_FOUND, ex.getCode(), ex.getMessage());
    }

    @ExceptionHandler(BusinessException.class)
    ResponseEntity<ErrorResponse> handleBusiness(BusinessException ex) {
        return error(ex.getStatus(), ex.getCode(), ex.getMessage());
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<ErrorResponse> handleDataIntegrity(DataIntegrityViolationException ex) {
        log.warn("Data integrity violation", ex);
        return error(HttpStatus.CONFLICT, "PAYMENT_CONFLICT", "Payment request conflicts with current state");
    }

    @ExceptionHandler({AsyncRequestNotUsableException.class, ClientAbortException.class})
    ResponseEntity<Void> handleClientAbort(Exception ex) {
        log.warn("Client aborted payment-service response: {}", shortMessage(ex));
        return ResponseEntity.status(499).build();
    }

    @ExceptionHandler(IOException.class)
    ResponseEntity<?> handleIoException(IOException ex) {
        if (isClientAbort(ex)) {
            log.warn("Client aborted payment-service response: {}", shortMessage(ex));
            return ResponseEntity.status(499).build();
        }
        log.error("Unexpected payment-service IO error", ex);
        return error(HttpStatus.INTERNAL_SERVER_ERROR, "PAYMENT_INTERNAL_ERROR", "Unexpected payment-service error");
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> handleUnexpected(Exception ex) {
        log.error("Unexpected payment-service error", ex);
        return error(HttpStatus.INTERNAL_SERVER_ERROR, "PAYMENT_INTERNAL_ERROR", "Unexpected payment-service error");
    }

    private ResponseEntity<ErrorResponse> error(HttpStatus status, String code, String message) {
        return ResponseEntity.status(status).body(new ErrorResponse(code, message, Instant.now()));
    }

    private boolean isClientAbort(Throwable ex) {
        Throwable current = ex;
        while (current != null) {
            if (current instanceof ClientAbortException || current instanceof AsyncRequestNotUsableException) {
                return true;
            }
            String message = current.getMessage();
            if (message != null) {
                String normalized = message.toLowerCase();
                if (normalized.contains("connection reset by peer")
                        || normalized.contains("connection reset")
                        || normalized.contains("broken pipe")
                        || normalized.contains("client abort")) {
                    return true;
                }
            }
            current = current.getCause();
        }
        return false;
    }

    private String shortMessage(Throwable ex) {
        String message = ex.getMessage();
        return message == null || message.isBlank()
                ? ex.getClass().getSimpleName()
                : message;
    }
}
