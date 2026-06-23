#!/usr/bin/env bash
# Install External Secrets Operator (ESO) on EKS via Helm (PETPLAT-34).
# ESO syncs secrets from AWS Secrets Manager into Kubernetes Secrets.
#
# Usage:
#   ./scripts/install-eso.sh <eso-role-arn>
#
# Arguments:
#   eso-role-arn   IRSA role ARN from: terraform output -raw eso_role_arn
#
# Example:
#   ./scripts/install-eso.sh arn:aws:iam::852396291743:role/petclinic-dev-eso-role

set -euo pipefail

ESO_HELM_VERSION="0.9.13"
ESO_NAMESPACE="external-secrets"
ESO_SA_NAME="external-secrets-sa"

ESO_ROLE_ARN="${1:?Usage: $0 <eso-role-arn>}"

echo "==> Adding External Secrets Helm repo..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

echo "==> Installing External Secrets Operator v${ESO_HELM_VERSION}..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --create-namespace \
  --version "${ESO_HELM_VERSION}" \
  --set serviceAccount.name="${ESO_SA_NAME}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait

echo "==> ESO pods:"
kubectl get pods -n "${ESO_NAMESPACE}"

echo ""
echo "==> Next: apply the ClusterSecretStore and ExternalSecret manifests:"
echo "    kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml"
echo "    kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml -n petclinic-dev"
echo "    kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml -n petclinic-dev"
