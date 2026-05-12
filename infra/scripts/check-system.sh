#!/usr/bin/env bash
# =============================================================
# MediQueue — Verificación rápida del estado del sistema
# Uso: bash scripts/check-system.sh
# =============================================================

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
  local name=$1
  local url=$2
  local response
  if response=$(curl -sf --max-time 5 "$url" 2>/dev/null); then
    local status
    status=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UP")
    if [ "$status" = "UP" ] || [ "$status" = "UP" ]; then
      echo -e "${GREEN}✅  ${name}: UP${NC}"
    else
      echo -e "${YELLOW}⚠️   ${name}: ${status}${NC}"
    fi
  else
    echo -e "${RED}❌  ${name}: DOWN${NC}"
  fi
}

echo ""
echo "══════════════════════════════════════════"
echo "  MediQueue — Estado del sistema"
echo "══════════════════════════════════════════"
echo ""

check "api-gateway-1       (8080)" "${GATEWAY_URL}/actuator/health"
check "api-gateway-2       (8090)" "http://localhost:8090/actuator/health"
check "patient-service     (8081)" "http://localhost:8081/actuator/health"
check "schedule-service    (8082)" "http://localhost:8082/actuator/health"
check "appointment-svc-1   (8083)" "http://localhost:8083/actuator/health"
check "appointment-svc-2   (8093)" "http://localhost:8093/actuator/health"
check "payment-svc-1       (8084)" "http://localhost:8084/actuator/health"
check "payment-svc-2       (8094)" "http://localhost:8094/actuator/health"
check "notification-svc    (8085)" "http://localhost:8085/actuator/health"   # interno: 8080 → externo: 8085
check "prometheus           (9090)" "http://localhost:9090/-/healthy"
check "grafana              (3000)" "http://localhost:3000/api/health"

echo ""
echo "──────────────────────────────────────────"
echo "  RabbitMQ queues:"
docker exec rabbitmq rabbitmqctl list_queues name messages consumers 2>/dev/null || \
  echo -e "${RED}  RabbitMQ: no disponible${NC}"

echo ""
echo "──────────────────────────────────────────"
echo "  Redis:"
docker exec redis redis-cli -a "${REDIS_PASSWORD:-redis123}" ping 2>/dev/null || \
  echo -e "${RED}  Redis: no disponible${NC}"

echo ""
