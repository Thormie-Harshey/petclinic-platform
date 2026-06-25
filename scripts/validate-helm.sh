#!/usr/bin/env bash
# Validates the generic Helm chart for all 8 Petclinic services across both environments.
# Runs: helm lint, helm template, kubectl apply --dry-run=client
# Usage: ./scripts/validate-helm.sh [--env dev|prod] [--service <name>]
set -euo pipefail

CHART="helm/petclinic-service"
SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)
ENVS=(dev prod)
FILTER_ENV=""
FILTER_SERVICE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)     FILTER_ENV="$2";     shift 2 ;;
    --service) FILTER_SERVICE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; echo "Usage: $0 [--env dev|prod] [--service <name>]"; exit 1 ;;
  esac
done

PASS=0
FAIL=0

run() {
  local label="$1"; shift
  if "$@" > /tmp/helm-validate-out.txt 2>&1; then
    echo "  [OK]  $label"
    ((PASS++))
  else
    echo "  [FAIL] $label"
    cat /tmp/helm-validate-out.txt
    ((FAIL++))
  fi
}

echo ""
echo "=== helm lint (chart defaults only) ==="
run "lint defaults" helm lint "$CHART"

for env in "${ENVS[@]}"; do
  [[ -n "$FILTER_ENV" && "$env" != "$FILTER_ENV" ]] && continue

  echo ""
  echo "=== Environment: $env ==="

  for svc in "${SERVICES[@]}"; do
    [[ -n "$FILTER_SERVICE" && "$svc" != "$FILTER_SERVICE" ]] && continue

    ns="petclinic-${env}"
    svc_values="helm-values/${svc}.yaml"
    env_values="helm-values/${env}.yaml"
    out_file="/tmp/helm-${svc}-${env}.yaml"

    echo ""
    echo "  --- $svc ---"

    run "lint   $svc/$env" \
      helm lint "$CHART" -f "$svc_values" -f "$env_values"

    if helm template "$svc" "$CHART" \
        -n "$ns" \
        -f "$svc_values" \
        -f "$env_values" \
        > "$out_file" 2>/tmp/helm-validate-out.txt; then
      echo "  [OK]  template $svc/$env → $out_file"
      ((PASS++))
    else
      echo "  [FAIL] template $svc/$env"
      cat /tmp/helm-validate-out.txt
      ((FAIL++))
      continue
    fi

    run "dry-run $svc/$env" \
      kubectl apply --dry-run=client -f "$out_file"
  done
done

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]]
