package com.mediqueue.payment.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {

    public static final String APPOINTMENTS_EXCHANGE = "appointments-exchange";
    public static final String PAYMENTS_EXCHANGE = "payments-exchange";
    public static final String APPOINTMENT_HELD_QUEUE = "payment.appointment-held.queue";
    public static final String APPOINTMENT_HELD_ROUTING_KEY = "appointment.held";
    public static final String PAYMENT_SUCCEEDED_ROUTING_KEY = "payment.succeeded";
    public static final String PAYMENT_FAILED_ROUTING_KEY = "payment.failed";

    @Bean
    DirectExchange appointmentsExchange() {
        return new DirectExchange(APPOINTMENTS_EXCHANGE, true, false);
    }

    @Bean
    DirectExchange paymentsExchange() {
        return new DirectExchange(PAYMENTS_EXCHANGE, true, false);
    }

    @Bean
    Queue appointmentHeldQueue() {
        return new Queue(APPOINTMENT_HELD_QUEUE, true);
    }

    @Bean
    Binding appointmentHeldBinding(Queue appointmentHeldQueue, DirectExchange appointmentsExchange) {
        return BindingBuilder.bind(appointmentHeldQueue)
                .to(appointmentsExchange)
                .with(APPOINTMENT_HELD_ROUTING_KEY);
    }

    @Bean
    MessageConverter messageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
