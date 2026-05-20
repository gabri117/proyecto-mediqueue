# Appointment Dataset

The official Block 2 appointment k6 scripts require a JSON dataset with real IDs from the running MediQueue stack.

## Contract

```json
{
  "metadata": {
    "appointmentCount": 50000
  },
  "appointments": [
    {
      "patientId": "uuid",
      "dentistId": "uuid",
      "slotId": "uuid",
      "appointmentDate": "2026-07-01",
      "startTime": "08:00:00",
      "endTime": "08:30:00",
      "amount": 150.00,
      "notes": "text"
    }
  ]
}
```

## Rules

- `slotId` must be unique for every successful appointment.
- `patientId` must not be null and must be a real backend UUID.
- `dentistId` must not be null and is copied from the real slot.
- `amount` is required by `AppointmentRequest`.
- `appointmentDate`, `startTime`, and `endTime` are copied from the slot when available.
- The generator never invents UUIDs.
- `appointments.sample.json` intentionally starts empty until generated from a real backend.

## Generate a Real Dataset

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 50000 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -Amount 150.00
```

For a quick local smoke dataset:

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 10 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments.sample.json `
  -Amount 150.00
```

`patient-ids.json` can be a plain array of UUIDs:

```json
[
  "11111111-1111-1111-1111-111111111111",
  "22222222-2222-2222-2222-222222222222"
]
```

If `/api/slots/available` returns fewer unique slots than requested, the generator stops with:

```text
No hay suficientes slots únicos para generar N citas. Ejecuta primero el seed.
```
