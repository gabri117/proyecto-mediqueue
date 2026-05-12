package com.mediqueue.schedule.exception;

import jakarta.persistence.EntityNotFoundException;
import java.time.Instant;
import java.util.stream.Collectors;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(EntityNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleEntityNotFoundException(EntityNotFoundException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(
                new ErrorResponse(
                        "NOT_FOUND",
                        exception.getMessage(),
                        Instant.now()
                )
        );
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorResponse> handleDataIntegrityViolationException(DataIntegrityViolationException exception) {
        if (exception.getMessage() != null && exception.getMessage().contains("email")) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(
                    new ErrorResponse(
                            "CONFLICT",
                            "Email already exists",
                            Instant.now()
                    )
            );
        }

        return ResponseEntity.status(HttpStatus.CONFLICT).body(
                new ErrorResponse(
                        "CONFLICT",
                        "Database constraint violation",
                        Instant.now()
                )
        );
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleMethodArgumentNotValidException(MethodArgumentNotValidException exception) {
        String message = exception.getBindingResult().getFieldErrors()
                .stream()
                .map(error -> error.getDefaultMessage())
                .collect(Collectors.joining(", "));

        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(
                new ErrorResponse(
                        "VALIDATION_ERROR",
                        message,
                        Instant.now()
                )
        );
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleException(Exception exception) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(
                new ErrorResponse(
                        "INTERNAL_SERVER_ERROR",
                        exception.getMessage(),
                        Instant.now()
                )
        );
    }
}
