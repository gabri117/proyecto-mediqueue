package com.mediqueue.appointment;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class MediqueueAppointmentServiceApplicationTests {

	@Test
	void applicationClassIsLoadable() {
		assertDoesNotThrow(() -> Class.forName(MediqueueAppointmentServiceApplication.class.getName()));
	}

}
