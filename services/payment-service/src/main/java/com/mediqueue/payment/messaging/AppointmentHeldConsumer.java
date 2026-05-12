package com.mediqueue.payment.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mediqueue.payment.config.RabbitMQConfig;
import com.mediqueue.payment.events.consumed.AppointmentHeldEvent;
import com.mediqueue.payment.exception.BusinessException;
import com.mediqueue.payment.service.PaymentService;
import com.rabbitmq.client.Channel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class AppointmentHeldConsumer {

    private final PaymentService paymentService;
    private final ObjectMapper objectMapper;

    @RabbitListener(queues = RabbitMQConfig.APPOINTMENT_HELD_QUEUE)
    public void consume(Message message, Channel channel) throws Exception {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            AppointmentHeldEvent event = objectMapper.readValue(message.getBody(), AppointmentHeldEvent.class);
            paymentService.processAppointmentHeld(event);
            channel.basicAck(deliveryTag, false);
        } catch (BusinessException ex) {
            log.warn("AppointmentHeld event rejected by business rule: {}", ex.getMessage());
            channel.basicAck(deliveryTag, false);
        } catch (IllegalArgumentException ex) {
            log.warn("Invalid AppointmentHeld event payload: {}", ex.getMessage());
            channel.basicAck(deliveryTag, false);
        } catch (Exception ex) {
            log.error("Unexpected error consuming AppointmentHeld event", ex);
            channel.basicNack(deliveryTag, false, true);
        }
    }
}
