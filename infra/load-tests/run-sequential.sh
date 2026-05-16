#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION_PROFILE="${DURATION_PROFILE:-normal}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-false}"
INCLUDE_HOSTILE="${INCLUDE_HOSTILE:-false}"
INCLUDE_E2E="${INCLUDE_E2E:-false}"
K6_OUTPUT_PROMETHEUS="${K6_OUTPUT_PROMETHEUS:-false}"
K6_BINARY="${K6_BINARY:-k6}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

case "${DURATION_PROFILE}" in
  smoke)
    export SMOKE_ITERATIONS="${SMOKE_ITERATIONS:-5}"
    export PATIENT_VUS="${PATIENT_VUS:-1}" PATIENT_DURATION="${PATIENT_DURATION:-15s}"
    export SCHEDULE_VUS="${SCHEDULE_VUS:-1}" SCHEDULE_DURATION="${SCHEDULE_DURATION:-15s}"
    export PAYMENT_VUS="${PAYMENT_VUS:-1}" PAYMENT_DURATION="${PAYMENT_DURATION:-15s}"
    export NOTIFICATION_VUS="${NOTIFICATION_VUS:-1}" NOTIFICATION_DURATION="${NOTIFICATION_DURATION:-15s}"
    ;;
  heavy)
    export SMOKE_ITERATIONS="${SMOKE_ITERATIONS:-10}"
    export PATIENT_VUS="${PATIENT_VUS:-50}" PATIENT_DURATION="${PATIENT_DURATION:-3m}"
    export SCHEDULE_VUS="${SCHEDULE_VUS:-200}" SCHEDULE_DURATION="${SCHEDULE_DURATION:-5m}"
    export PAYMENT_VUS="${PAYMENT_VUS:-100}" PAYMENT_DURATION="${PAYMENT_DURATION:-5m}"
    export NOTIFICATION_VUS="${NOTIFICATION_VUS:-100}" NOTIFICATION_DURATION="${NOTIFICATION_DURATION:-5m}"
    ;;
  normal) ;;
  *) echo "DURATION_PROFILE invalido: ${DURATION_PROFILE}" >&2; exit 2 ;;
esac

PHASES=(
  "00 Smoke|infra/load-tests/scripts/00-smoke.js"
  "01 Patient Load|infra/load-tests/scripts/01-patient-load.js"
  "02 Schedule Load|infra/load-tests/scripts/02-schedule-load.js"
  "03 Payment Load|infra/load-tests/scripts/03-payment-load.js"
  "04 Notification Load|infra/load-tests/scripts/04-notification-load.js"
)

if [[ "${INCLUDE_HOSTILE}" == "true" ]]; then
  PHASES+=("05 Appointment Hostile|infra/load-tests/scripts/05-appointment-hostile.js")
fi

if [[ "${INCLUDE_E2E}" == "true" ]]; then
  export ALLOW_E2E=true
  PHASES+=("06 E2E Flow|infra/load-tests/scripts/06-e2e-flow.js")
fi

cd "${REPO_ROOT}"
export BASE_URL RESULTS_DIR

FAILED=0
for phase in "${PHASES[@]}"; do
  name="${phase%%|*}"
  script="${phase#*|}"
  export K6_SCRIPT_NAME="$(basename "${script}")"

  args=(run)
  if [[ "${K6_OUTPUT_PROMETHEUS}" == "true" ]]; then
    export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-http://localhost:9090/api/v1/write}"
    args+=(-o experimental-prometheus-rw)
  fi
  args+=("${script}")

  echo
  echo "==> ${name}"
  echo "Command: ${K6_BINARY} ${args[*]}"

  started="$(date +%s)"
  if "${K6_BINARY}" "${args[@]}"; then
    exit_code=0
  else
    exit_code=$?
  fi
  elapsed="$(( $(date +%s) - started ))s"
  echo "Phase=${name} ExitCode=${exit_code} Duration=${elapsed}"

  if [[ "${name}" == 00* && "${exit_code}" -ne 0 ]]; then
    echo "Smoke fallo; se detiene la suite secuencial."
    FAILED=1
    break
  fi

  if [[ "${exit_code}" -ne 0 ]]; then
    FAILED=1
    if [[ "${CONTINUE_ON_ERROR}" != "true" ]]; then
      echo "Fase fallo y CONTINUE_ON_ERROR no esta activo; se detiene la suite."
      break
    fi
  fi
done

exit "${FAILED}"
