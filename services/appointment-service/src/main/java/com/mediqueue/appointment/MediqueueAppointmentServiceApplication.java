package com.mediqueue.appointment;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class MediqueueAppointmentServiceApplication {

	public static void main(String[] args) {
		SpringApplication.run(MediqueueAppointmentServiceApplication.class, args);
	}

}
