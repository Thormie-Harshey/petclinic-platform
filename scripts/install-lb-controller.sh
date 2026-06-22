#!/usr/bin/env bash
# Install the AWS Load Balancer Controller on an EKS cluster via Helm.
#
# IMPORTANT — VERSION NUMBERING:
#   The controller application and its Helm chart use DIFFERENT version schemes.
#   CRDs must be fetched using the CONTROLLER application version tag (e.g. v2.8.1).
#   Using the Helm chart version (e.g. 1.8.1) in the GitHub URL will return a 404.
#
# Usage:
#   ./scripts/install-lb-controller.sh <cluster-name> <lb-controller-role-arn> [aws-region]
#
# Example:
#   ./scripts/install-lb-controller.sh \
#     petclinic-dev \
#     arn:aws:iam::123456789012:role/petclinic-dev-lb-controller-role \
#     eu-central-1
#
# Prerequisites:
#   - kubectl configured for the target cluster (aws eks update-kubeconfig ...)
#   - helm >= 3.x installed
#   - aws CLI configured with sufficient permissions

set -euo pipefail

# ── Versions ──────────────────────────────────────────────────────────────────
# Controller application version — used for CRD GitHub URL
CONTROLLER_VERSION="v2.8.1"
# Helm chart version — different numbering from the application version
HELM_CHART_VERSION="1.8.1"

# ── Arguments ─────────────────────────────────────────────────────────────────
CLUSTER_NAME="${1:?ERROR: cluster-name is required. Usage: $0 <cluster-name> <lb-controller-role-arn> [aws-region]}"
LB_CONTROLLER_ROLE_ARN="${2:?ERROR: lb-controller-role-arn is required. Get it from: terraform output -raw lb_controller_role_arn}"
AWS_REGION="${3:-eu-central-1}"

echo "================================================================"
echo " AWS Load Balancer Controller Installer"
echo "================================================================"
echo " Cluster:            ${CLUSTER_NAME}"
echo " Region:             ${AWS_REGION}"
echo " Controller version: ${CONTROLLER_VERSION}  (application)"
echo " Helm chart version: ${HELM_CHART_VERSION}  (different numbering!)"
echo " IRSA Role ARN:      ${LB_CONTROLLER_ROLE_ARN}"
echo "================================================================"
echo ""

# ── Step 1: Install CRDs ──────────────────────────────────────────────────────
# Uses the CONTROLLER application version tag (not Helm chart version).
# The controller repo (kubernetes-sigs/aws-load-balancer-controller) tags match
# the application version. The Helm chart repo (aws/eks-charts) uses its own version.
echo "==> [1/4] Installing CRDs from controller repo (${CONTROLLER_VERSION})..."
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${CONTROLLER_VERSION}/helm/aws-load-balancer-controller/crds/crds.yaml"

# ── Step 2: Add EKS Helm chart repository ─────────────────────────────────────
echo ""
echo "==> [2/4] Adding EKS Helm chart repository..."
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

# ── Step 3: Resolve VPC ID from the cluster ───────────────────────────────────
echo ""
echo "==> [3/4] Resolving VPC ID from cluster '${CLUSTER_NAME}'..."
VPC_ID=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)
echo "    VPC ID: ${VPC_ID}"

# ── Step 4: Install the controller via Helm ───────────────────────────────────
echo ""
echo "==> [4/4] Installing AWS Load Balancer Controller (Helm chart ${HELM_CHART_VERSION})..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "${HELM_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LB_CONTROLLER_ROLE_ARN}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait \
  --timeout 120s

# ── Verify ─────────────────────────────────────────────────────────────────────
echo ""
echo "==> Verifying controller deployment..."
kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=120s

echo ""
echo "================================================================"
echo " Installation complete!"
echo "================================================================"
echo ""
echo "Verify pods are running:"
echo "  kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
echo ""
echo "Next steps (PETPLAT-30 and PETPLAT-31):"
echo "  1. Get your ACM certificate ARN:"
echo "       terraform -chdir=terraform/environments/dev output -raw acm_certificate_arn"
echo ""
echo "  2. Get your ALB security group ID:"
echo "       terraform -chdir=terraform/environments/dev output -raw alb_sg_id"
echo ""
echo "  3. Replace the two placeholders in k8s/base/ingress/ingress.yaml"
echo "     then apply:"
echo "       kubectl apply -f k8s/base/ingress/ingress.yaml -n petclinic-dev"
echo ""
echo "  4. Wait ~2-3 min for the ALB to provision, then get its DNS name:"
echo "       kubectl get ingress -n petclinic-dev \\"
echo "         -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "  5. Add this to terraform/environments/dev/terraform.tfvars:"
echo "       alb_dns_name = \"<the ALB hostname from step 4>\""
echo ""
echo "  6. Run terraform apply again to create the Route 53 A record (PETPLAT-31):"
echo "       terraform -chdir=terraform/environments/dev apply"
echo "================================================================"
