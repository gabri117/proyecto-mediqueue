package com.mediqueue.appointment.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Declares all RabbitMQ exchanges, queues, and bindings used by the
 * appointment service.
 *
 * <p>Uses {@link Jackson2JsonMessageConverter} so that events are
 * automatically serialized/deserialized as JSON.</p>
 *
 * @since 0.0.1
 */
@Configuration
public class RabbitMQConfig {

    // =========================================================================
    // Exchanges
    // =========================================================================

    @Bean
    public DirectExchange appointmentsExchange() {
        return new DirectExchange("appointments-exchange", true, false);
    }

    @Bean
    public DirectExchange paymentsExchange() {
        return new DirectExchange("payments-exchange", true, false);
    }

    // =========================================================================
    // Queues — Payment events (consumed by this service)
    // =========================================================================

    @Bean
    public Queue paymentSucceededQueue() {
        return QueueBuilder.durable("payment.succeeded").build();
    }

    @Bean
    public Queue paymentFailedQueue() {
        return QueueBuilder.durable("payment.failed").build();
    }

    // =========================================================================
    // Bindings — payments-exchange
    // =========================================================================

    @Bean
    public Binding bindingPaymentSucceeded(Queue paymentSucceededQueue, DirectExchange paymentsExchange) {
        return BindingBuilder.bind(paymentSucceededQueue).to(paymentsExchange).with("payment.succeeded");
    }

    @Bean
    public Binding bindingPaymentFailed(Queue paymentFailedQueue, DirectExchange paymentsExchange) {
        return BindingBuilder.bind(paymentFailedQueue).to(paymentsExchange).with("payment.failed");
    }

    // =========================================================================
    // Message Converter
    // =========================================================================

    @Bean
    public MessageConverter jackson2JsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
