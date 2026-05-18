package com.mediqueue.payment.exception;

import com.mediqueue.payment.dto.ErrorResponse;
import java.io.IOException;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;

class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void connectionResetByPeerIsTreatedAsClientAbort() {
        ResponseEntity<?> response = handler.handleIoException(new IOException("Connection reset by peer"));

        assertThat(response.getStatusCode().value()).isEqualTo(499);
        assertThat(response.getBody()).isNull();
    }

    @Test
    void nestedConnectionResetByPeerIsTreatedAsClientAbort() {
        ResponseEntity<?> response = handler.handleIoException(new IOException(
                "Response write failed",
                new IOException("Connection reset by peer")));

        assertThat(response.getStatusCode().value()).isEqualTo(499);
        assertThat(response.getBody()).isNull();
    }

    @Test
    void unrelatedIoExceptionRemainsInternalServerError() {
        ResponseEntity<?> response = handler.handleIoException(new IOException("Disk read failed"));

        assertThat(response.getStatusCode().value()).isEqualTo(500);
        assertThat(response.getBody())
                .isInstanceOf(ErrorResponse.class)
                .extracting("code")
                .isEqualTo("PAYMENT_INTERNAL_ERROR");
    }
}
