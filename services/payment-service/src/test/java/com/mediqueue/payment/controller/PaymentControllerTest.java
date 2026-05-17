package com.mediqueue.payment.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.payment.domain.enums.PaymentStatus;
import com.mediqueue.payment.dto.PagedResponse;
import com.mediqueue.payment.dto.PaymentRequest;
import com.mediqueue.payment.dto.PaymentResponse;
import com.mediqueue.payment.service.PaymentService;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(PaymentController.class)
class PaymentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private PaymentService paymentService;

    @Test
    void postPaymentWithoutIdempotencyKeyReturnsBadRequest() throws Exception {
        PaymentRequest request = new PaymentRequest(UUID.randomUUID(), UUID.randomUUID(), BigDecimal.TEN, "GTQ");

        mockMvc.perform(post("/payments")
                        .contentType("application/json")
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void postPaymentWithZeroAmountReturnsBadRequest() throws Exception {
        PaymentRequest request = new PaymentRequest(UUID.randomUUID(), UUID.randomUUID(), BigDecimal.ZERO, "GTQ");

        mockMvc.perform(post("/payments")
                        .header("X-Idempotency-Key", "manual-key")
                        .contentType("application/json")
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void postPaymentWithMalformedJsonReturnsBadRequest() throws Exception {
        mockMvc.perform(post("/payments")
                        .header("X-Idempotency-Key", "manual-key")
                        .contentType("application/json")
                        .content("{appointmentId:\"bad-json\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("PAYMENT_BAD_REQUEST"))
                .andExpect(jsonPath("$.message").value("Malformed request body"));
    }

    @Test
    void getPaymentsWithoutParametersReturnsPagedResponse() throws Exception {
        when(paymentService.getPayments(null, null, 0, 20)).thenReturn(pagedResponse(0, 20));

        mockMvc.perform(get("/payments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").isArray())
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(20))
                .andExpect(jsonPath("$.totalElements").value(0))
                .andExpect(jsonPath("$.totalPages").value(0))
                .andExpect(jsonPath("$.first").value(true))
                .andExpect(jsonPath("$.last").value(true));
    }

    @Test
    void getPaymentsWithPageAndSizeReturnsRequestedSize() throws Exception {
        when(paymentService.getPayments(null, null, 0, 10)).thenReturn(pagedResponse(0, 10));

        mockMvc.perform(get("/payments?page=0&size=10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.size").value(10));
    }

    @Test
    void getPaymentsWithStatusCallsServiceWithApprovedStatus() throws Exception {
        when(paymentService.getPayments(null, PaymentStatus.APPROVED, 0, 20)).thenReturn(pagedResponse(0, 20));

        mockMvc.perform(get("/payments?status=APPROVED"))
                .andExpect(status().isOk());

        verify(paymentService).getPayments(null, PaymentStatus.APPROVED, 0, 20);
    }

    @Test
    void getPaymentsWithAppointmentIdWorksPaged() throws Exception {
        UUID appointmentId = UUID.randomUUID();
        when(paymentService.getPayments(appointmentId, null, 0, 20)).thenReturn(pagedResponse(0, 20));

        mockMvc.perform(get("/payments?appointmentId={appointmentId}", appointmentId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").isArray());
    }

    @Test
    void getPaymentsWithAppointmentIdAndStatusCombinesFilters() throws Exception {
        UUID appointmentId = UUID.randomUUID();
        when(paymentService.getPayments(appointmentId, PaymentStatus.APPROVED, 0, 20)).thenReturn(pagedResponse(0, 20));

        mockMvc.perform(get("/payments?appointmentId={appointmentId}&status=APPROVED", appointmentId))
                .andExpect(status().isOk());

        verify(paymentService).getPayments(eq(appointmentId), eq(PaymentStatus.APPROVED), eq(0), eq(20));
    }

    @Test
    void getPaymentsWithLargeSizeReturnsCappedSizeFromService() throws Exception {
        when(paymentService.getPayments(null, null, 0, 1000)).thenReturn(pagedResponse(0, 100));

        mockMvc.perform(get("/payments?size=1000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.size").value(100));
    }

    @Test
    void getPaymentsWithInvalidStatusReturnsBadRequest() throws Exception {
        mockMvc.perform(get("/payments?status=NO_EXISTE"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("PAYMENT_BAD_REQUEST"))
                .andExpect(jsonPath("$.message").value("Invalid parameter value"));
    }

    private PagedResponse<PaymentResponse> pagedResponse(int page, int size) {
        return new PagedResponse<>(List.of(), page, size, 0, 0, true, true);
    }
}
