#!/usr/bin/env bash
# Authenticate Docker to the ECR private registry in eu-central-1.
# The login token is valid for 12 hours — re-run when it expires.
#
# Usage:
#   ./scripts/ecr-login.sh [--region eu-central-1]
#
# Prerequisites:
#   - AWS CLI configured (aws configure or AWS_PROFILE / instance role)
#   - Docker daemon running
set -euo pipefail

REGION="eu-central-1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--region eu-central-1]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--region eu-central-1]" >&2
      exit 1
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR: ${ECR_REGISTRY}"
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "ECR login successful. Token valid for 12 hours."
echo "Registry: ${ECR_REGISTRY}"
