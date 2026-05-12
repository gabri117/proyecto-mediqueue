package com.mediqueue.appointment.service;

import com.mediqueue.appointment.domain.enums.AppointmentStatus;
import com.mediqueue.appointment.exception.IllegalStateTransitionException;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Set;

/**
 * Validates appointment status transitions against a predefined state machine.
 *
 * <p>Only the following transitions are allowed:</p>
 * <ul>
 *   <li>{@code PENDING_PAYMENT → CONFIRMED}</li>
 *   <li>{@code PENDING_PAYMENT → CANCELLED}</li>
 *   <li>{@code PENDING_PAYMENT → EXPIRED}</li>
 * </ul>
 *
 * <p>Any other transition triggers an {@link IllegalStateTransitionException}.</p>
 *
 * @since 0.0.1
 */
@Component
public class AppointmentStateMachine {

    private static final Map<AppointmentStatus, Set<AppointmentStatus>> ALLOWED_TRANSITIONS = Map.of(
            AppointmentStatus.PENDING_PAYMENT, Set.of(
                    AppointmentStatus.CONFIRMED,
                    AppointmentStatus.CANCELLED,
                    AppointmentStatus.EXPIRED
            )
    );

    /**
     * Validates that a transition from one status to another is permitted.
     *
     * @param from the current appointment status
     * @param to   the target appointment status
     * @throws IllegalStateTransitionException if the transition is not allowed
     */
    public void validate(AppointmentStatus from, AppointmentStatus to) {
        Set<AppointmentStatus> targets = ALLOWED_TRANSITIONS.getOrDefault(from, Set.of());

        if (!targets.contains(to)) {
            throw new IllegalStateTransitionException(
                    "Transición inválida: " + from + " → " + to
            );
        }
    }
}
