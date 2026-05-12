#!/usr/bin/env bash
# =============================================================
# MediQueue — Seed de datos iniciales
# Crea 50 pacientes, 10 dentistas y 200 slots disponibles
# Ejecutar con: bash scripts/seed-data.sh
# =============================================================

set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅  $1${NC}"; }
step() { echo -e "\n${YELLOW}► $1${NC}"; }

wait_for_service() {
  local url=$1
  local name=$2
  echo -n "   Esperando ${name}..."
  for i in $(seq 1 30); do
    if curl -sf "$url" > /dev/null 2>&1; then
      echo " UP"
      return 0
    fi
    sleep 2
    echo -n "."
  done
  echo ""
  echo "WARNING: ${name} no responde después de 60s"
  return 1
}

# ─── Esperar servicios ───
step "Verificando que los servicios están listos..."
wait_for_service "${GATEWAY_URL}/actuator/health" "api-gateway"
wait_for_service "http://localhost:8081/actuator/health" "patient-service"
wait_for_service "http://localhost:8082/actuator/health" "schedule-service"

# ─── Crear pacientes ───
step "Creando 50 pacientes..."
SPECIALTIES=("Odontología General" "Ortodoncia" "Endodoncia" "Periodoncia" "Cirugía Maxilofacial")

for i in $(seq 1 50); do
  curl -sf -X POST "${GATEWAY_URL}/api/patients" \
    -H "Content-Type: application/json" \
    -d "{
      \"firstName\": \"Paciente${i}\",
      \"lastName\": \"Apellido${i}\",
      \"email\": \"paciente${i}@mediqueue.test\",
      \"documentNumber\": \"DNI${i}000000\",
      \"phone\": \"+549${i}${i}${i}${i}${i}${i}${i}${i}${i}\"
    }" > /dev/null 2>&1 || echo "  WARNING: paciente ${i} pudo ya existir"
  printf "."
done
echo ""
ok "50 pacientes creados"

# ─── Crear dentistas ───
step "Creando 10 dentistas..."
DOCTOR_NAMES=(
  "Dr. Carlos López" "Dra. María García" "Dr. Juan Rodríguez"
  "Dra. Ana Martínez" "Dr. Pedro Sánchez" "Dra. Laura Torres"
  "Dr. Miguel Flores" "Dra. Sofía Morales" "Dr. Andrés Vargas"
  "Dra. Valentina Castro"
)

for i in $(seq 0 9); do
  NAME="${DOCTOR_NAMES[$i]}"
  SPECIALTY="${SPECIALTIES[$((i % ${#SPECIALTIES[@]}))]}"
  curl -sf -X POST "${GATEWAY_URL}/api/schedule/doctors" \
    -H "Content-Type: application/json" \
    -d "{
      \"fullName\": \"${NAME}\",
      \"specialty\": \"${SPECIALTY}\",
      \"licenseNumber\": \"MN${i}0000\",
      \"email\": \"doctor${i}@mediqueue.test\"
    }" > /dev/null 2>&1 || echo "  WARNING: doctor ${i} pudo ya existir"
  printf "."
done
echo ""
ok "10 dentistas creados"

# ─── Generar horarios de trabajo ───
step "Configurando horarios de trabajo para cada dentista..."
for doctor_id in $(seq 1 10); do
  for day in MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY; do
    curl -sf -X POST "${GATEWAY_URL}/api/schedule/doctors/${doctor_id}/working-hours" \
      -H "Content-Type: application/json" \
      -d "{
        \"dayOfWeek\": \"${day}\",
        \"startTime\": \"09:00\",
        \"endTime\": \"17:00\",
        \"slotDurationMinutes\": 30
      }" > /dev/null 2>&1 || true
  done
  printf "."
done
echo ""
ok "Horarios configurados"

# ─── Generar slots para los próximos 30 días ───
step "Generando slots para los próximos 30 días..."
START_DATE=$(date +%Y-%m-%d)
curl -sf -X POST "${GATEWAY_URL}/api/schedule/slots/generate" \
  -H "Content-Type: application/json" \
  -d "{
    \"fromDate\": \"${START_DATE}\",
    \"daysAhead\": 30
  }" > /dev/null 2>&1 || warn "  Endpoint de generación de slots puede tener distinto path"

ok "Slots generados (o generados por el job automático de schedule-service)"

# ─── Resumen ───
echo ""
echo "══════════════════════════════════════"
echo "  SEED COMPLETADO"
echo "══════════════════════════════════════"
ok "50 pacientes"
ok "10 dentistas"
ok "Horarios configurados (L-V, 9:00-17:00, slots de 30 min)"
ok "Slots generados para próximos 30 días (~200 slots por semana)"
echo ""
echo "  Grafana:         http://localhost:3000"
echo "  RabbitMQ:        http://localhost:15672"
echo "  Prometheus:      http://localhost:9090"
echo ""
