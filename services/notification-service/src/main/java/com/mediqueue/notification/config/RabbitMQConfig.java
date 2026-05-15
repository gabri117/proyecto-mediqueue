package com.mediqueue.notification.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.springframework.amqp.core.AcknowledgeMode;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Declarables;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.Arrays;
import java.util.List;

@Configuration
public class RabbitMQConfig {

    public static final String QUEUE_NOTIFICATION_APPOINTMENT = "notification.appointment.queue";
    public static final String QUEUE_NOTIFICATION_PAYMENT     = "notification.payment.queue";

    @Bean
    DirectExchange notificationAppointmentsExchange(
            @Value("${notification.rabbitmq.appointments-exchange:appointments-exchange}") String exchangeName) {
        return new DirectExchange(exchangeName, true, false);
    }

    @Bean
    DirectExchange notificationPaymentsExchange(
            @Value("${notification.rabbitmq.payments-exchange:payments-exchange}") String exchangeName) {
        return new DirectExchange(exchangeName, true, false);
    }

    @Bean
    Queue notificationAppointmentQueue(
            @Value("${notification.rabbitmq.appointment-queue:notification.appointment.queue}") String queueName,
            @Value("${notification.rabbitmq.dead-letter-exchange:notifications.dlx}") String deadLetterExchange,
            @Value("${notification.rabbitmq.appointment-dead-letter-routing-key:notification.appointment.dlq}") String deadLetterRoutingKey) {
        return QueueBuilder.durable(queueName)
                .deadLetterExchange(deadLetterExchange)
                .deadLetterRoutingKey(deadLetterRoutingKey)
                .build();
    }

    @Bean
    Queue notificationPaymentQueue(
            @Value("${notification.rabbitmq.payment-queue:notification.payment.queue}") String queueName,
            @Value("${notification.rabbitmq.dead-letter-exchange:notifications.dlx}") String deadLetterExchange,
            @Value("${notification.rabbitmq.payment-dead-letter-routing-key:notification.payment.dlq}") String deadLetterRoutingKey) {
        return QueueBuilder.durable(queueName)
                .deadLetterExchange(deadLetterExchange)
                .deadLetterRoutingKey(deadLetterRoutingKey)
                .build();
    }

    @Bean
    Declarables notificationAppointmentBindings(
            Queue notificationAppointmentQueue,
            DirectExchange notificationAppointmentsExchange,
            @Value("${notification.rabbitmq.appointment-routing-keys:appointment.confirmed,appointment.cancelled,appointment.expired}") String routingKeys) {
        List<Binding> bindings = Arrays.stream(routingKeys.split(","))
                .map(String::trim)
                .filter(key -> !key.isEmpty())
                .map(key -> BindingBuilder.bind(notificationAppointmentQueue)
                        .to(notificationAppointmentsExchange)
                        .with(key))
                .toList();
        return new Declarables(bindings.toArray(new Binding[0]));
    }

    @Bean
    Declarables notificationPaymentBindings(
            Queue notificationPaymentQueue,
            DirectExchange notificationPaymentsExchange,
            @Value("${notification.rabbitmq.payment-routing-keys:payment.succeeded,payment.failed}") String routingKeys) {
        List<Binding> bindings = Arrays.stream(routingKeys.split(","))
                .map(String::trim)
                .filter(key -> !key.isEmpty())
                .map(key -> BindingBuilder.bind(notificationPaymentQueue)
                        .to(notificationPaymentsExchange)
                        .with(key))
                .toList();
        return new Declarables(bindings.toArray(new Binding[0]));
    }

    @Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }

    @Bean
    public MessageConverter jackson2JsonMessageConverter(ObjectMapper objectMapper) {
        return new Jackson2JsonMessageConverter(objectMapper);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory,
                                         MessageConverter messageConverter) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(messageConverter);
        return template;
    }

    @Bean
    public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
            ConnectionFactory connectionFactory,
            MessageConverter messageConverter,
            @Value("${spring.rabbitmq.listener.simple.auto-startup:true}") boolean autoStartup) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(messageConverter);
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setPrefetchCount(10);
        factory.setAutoStartup(autoStartup);
        return factory;
    }
}
