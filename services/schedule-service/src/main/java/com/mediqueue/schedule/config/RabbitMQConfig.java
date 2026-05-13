package com.mediqueue.schedule.config;

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
 * RabbitMQ topology for schedule-service.
 *
 * <p>Creates a durable queue that binds to {@code appointments-exchange}
 * for each appointment routing key, plus a Dead-Letter Queue (DLQ) for
 * messages that exhaust all retry attempts configured in
 * {@code application.properties}.</p>
 *
 * <p>The exchange name {@code appointments-exchange} matches the exchange
 * declared and published to by {@code appointment-service}.</p>
 *
 * @since 0.0.2
 */
@Configuration
public class RabbitMQConfig {

    // =========================================================================
    // Exchange — declared but not owned here; appointment-service is the owner.
    // Spring AMQP will auto-declare it if not already present (idempotent).
    // =========================================================================

    @Bean
    public DirectExchange appointmentsExchange() {
        return new DirectExchange("appointments-exchange", true, false);
    }

    // =========================================================================
    // Dead Letter Exchange & Queue
    // =========================================================================

    @Bean
    public DirectExchange scheduleDeadLetterExchange() {
        return new DirectExchange("schedule.appointments.dlx", true, false);
    }

    @Bean
    public Queue scheduleAppointmentsDlq() {
        return QueueBuilder.durable("schedule.appointments.dlq").build();
    }

    @Bean
    public Binding scheduleAppointmentsDlqBinding(Queue scheduleAppointmentsDlq,
                                                   DirectExchange scheduleDeadLetterExchange) {
        return BindingBuilder.bind(scheduleAppointmentsDlq)
                .to(scheduleDeadLetterExchange)
                .with("schedule.appointments.dlq");
    }

    // =========================================================================
    // Queues — one per routing key for independent consumption and monitoring
    // =========================================================================

    @Bean
    public Queue scheduleAppointmentHeldQueue() {
        return QueueBuilder.durable("schedule.appointment.held")
                .withArgument("x-dead-letter-exchange", "schedule.appointments.dlx")
                .withArgument("x-dead-letter-routing-key", "schedule.appointments.dlq")
                .build();
    }

    @Bean
    public Queue scheduleAppointmentConfirmedQueue() {
        return QueueBuilder.durable("schedule.appointment.confirmed")
                .withArgument("x-dead-letter-exchange", "schedule.appointments.dlx")
                .withArgument("x-dead-letter-routing-key", "schedule.appointments.dlq")
                .build();
    }

    @Bean
    public Queue scheduleAppointmentCancelledQueue() {
        return QueueBuilder.durable("schedule.appointment.cancelled")
                .withArgument("x-dead-letter-exchange", "schedule.appointments.dlx")
                .withArgument("x-dead-letter-routing-key", "schedule.appointments.dlq")
                .build();
    }

    @Bean
    public Queue scheduleAppointmentExpiredQueue() {
        return QueueBuilder.durable("schedule.appointment.expired")
                .withArgument("x-dead-letter-exchange", "schedule.appointments.dlx")
                .withArgument("x-dead-letter-routing-key", "schedule.appointments.dlq")
                .build();
    }

    // =========================================================================
    // Bindings — map routing keys on appointments-exchange to local queues
    // =========================================================================

    @Bean
    public Binding bindingScheduleHeld(Queue scheduleAppointmentHeldQueue,
                                        DirectExchange appointmentsExchange) {
        return BindingBuilder.bind(scheduleAppointmentHeldQueue)
                .to(appointmentsExchange)
                .with("appointment.held");
    }

    @Bean
    public Binding bindingScheduleConfirmed(Queue scheduleAppointmentConfirmedQueue,
                                             DirectExchange appointmentsExchange) {
        return BindingBuilder.bind(scheduleAppointmentConfirmedQueue)
                .to(appointmentsExchange)
                .with("appointment.confirmed");
    }

    @Bean
    public Binding bindingScheduleCancelled(Queue scheduleAppointmentCancelledQueue,
                                             DirectExchange appointmentsExchange) {
        return BindingBuilder.bind(scheduleAppointmentCancelledQueue)
                .to(appointmentsExchange)
                .with("appointment.cancelled");
    }

    @Bean
    public Binding bindingScheduleExpired(Queue scheduleAppointmentExpiredQueue,
                                           DirectExchange appointmentsExchange) {
        return BindingBuilder.bind(scheduleAppointmentExpiredQueue)
                .to(appointmentsExchange)
                .with("appointment.expired");
    }

    // =========================================================================
    // Message Converter — must match appointment-service's Jackson converter
    // =========================================================================

    @Bean
    public MessageConverter jackson2JsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
