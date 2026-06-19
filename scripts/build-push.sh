#!/usr/bin/env bash
# Build all 8 Spring Petclinic microservices and push ARM64 images to ECR.
#
# Flow:
#   1. Maven builds JARs (no -P buildDocker — we handle image creation here)
#   2. Docker login to ECR
#   3. docker buildx builds linux/arm64 images (required for Graviton t4g EKS nodes)
#   4. Images pushed directly from buildx (--push flag)
#
# Usage:
#   ./scripts/build-push.sh <app-repo-path> [environment] [tag]
#
# Arguments:
#   app-repo-path   Path to spring-petclinic-microservices checkout
#   environment     Target ECR environment: dev or prod  (default: dev)
#   tag             Image tag pushed to ECR              (default: v1.0.0)
#
# Examples:
#   ./scripts/build-push.sh ../spring-petclinic-microservices dev v1.0.0
#   ./scripts/build-push.sh /home/user/microservices prod a1b2c3d
#
# Prerequisites:
#   - AWS CLI configured with ECR push permissions
#   - Docker with buildx enabled (Docker Desktop or `docker buildx install`)
#   - JDK 17 on PATH
#   - Maven wrapper (./mvnw) present in the application repo
set -euo pipefail

# --- Arguments ---
APP_REPO="${1:?ERROR: app-repo-path is required.
Usage: $0 <app-repo-path> [dev|prod] [tag]}"
ENVIRONMENT="${2:-dev}"
TAG="${3:-v1.0.0}"
REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

# --- Validate inputs ---
if [[ ! -d "$APP_REPO" ]]; then
  echo "ERROR: Application repo not found at: $APP_REPO" >&2
  exit 1
fi

case "$ENVIRONMENT" in
  dev|prod) ;;
  *) echo "ERROR: environment must be 'dev' or 'prod', got: $ENVIRONMENT" >&2; exit 1 ;;
esac

# --- Service definitions ---
# Format: "maven-module:ecr-service-name:exposed-port"
#
# IMPORTANT: Ports come from the technical-spec.md Service Inventory, NOT from pom.xml.
# Several pom.xml files have incorrect copy-paste port values (api-gateway, visits,
# vets, genai-service all show 8081). Always use the values below.
SERVICES=(
  "spring-petclinic-config-server:config-server:8888"
  "spring-petclinic-discovery-server:discovery-server:8761"
  "spring-petclinic-api-gateway:api-gateway:8080"
  "spring-petclinic-customers-service:customers-service:8081"
  "spring-petclinic-visits-service:visits-service:8082"
  "spring-petclinic-vets-service:vets-service:8083"
  "spring-petclinic-genai-service:genai-service:8084"
  "spring-petclinic-admin-server:admin-server:9090"
)

# ============================================================
# Step 1: Build JARs with Maven
# -DskipTests skips unit tests for speed; run tests separately
# before triggering this script in production workflows.
# ============================================================
echo ""
echo "=== Step 1: Building JARs with Maven ==="
echo "App repo : $APP_REPO"
(
  cd "$APP_REPO"
  ./mvnw clean install -DskipTests
)
echo "Maven build complete."

# ============================================================
# Step 2: Authenticate to ECR
# The login token is valid for 12 hours.
# ============================================================
echo ""
echo "=== Step 2: Authenticating to ECR ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "Registry: $ECR_REGISTRY"

aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
echo "ECR login successful."

# ============================================================
# Step 3: Set up Docker Buildx for ARM64 cross-compilation
#
# GitHub Actions runners and most developer laptops are x86_64.
# EKS nodes are ARM64 (Graviton t4g). Buildx + QEMU emulation
# bridges the gap — build time increases ~2-3x vs native ARM.
# ============================================================
echo ""
echo "=== Step 3: Setting up Docker Buildx (linux/arm64) ==="
BUILDER_NAME="petclinic-arm64-builder"
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
  docker buildx create --name "$BUILDER_NAME" --driver docker-container --bootstrap
else
  docker buildx inspect "$BUILDER_NAME" --bootstrap
fi
docker buildx use "$BUILDER_NAME"
echo "Buildx builder ready: $BUILDER_NAME"

# ============================================================
# Step 4: Build and push each service image
#
# Dockerfile: docker/Dockerfile (shared by all 8 services)
# Build args:
#   ARTIFACT_NAME — JAR filename without .jar extension
#   EXPOSED_PORT  — service HTTP port (metadata only, K8s controls actual binding)
#
# --push sends the image directly to ECR from the buildx builder.
# --provenance=false avoids OCI manifest index which ECR rejects
# when a single-platform image is pushed as multi-platform manifest.
# ============================================================
echo ""
echo "=== Step 4: Building and pushing ARM64 images ==="
echo "Environment : $ENVIRONMENT"
echo "Tag         : $TAG"
echo "Platform    : linux/arm64"
echo ""

DOCKERFILE="${APP_REPO}/docker/Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "ERROR: Dockerfile not found at $DOCKERFILE" >&2
  exit 1
fi

PUSHED_IMAGES=()

for service_def in "${SERVICES[@]}"; do
  # Parse the colon-delimited service definition
  MODULE="${service_def%%:*}"
  rest="${service_def#*:}"
  SERVICE="${rest%%:*}"
  PORT="${rest#*:}"

  # Locate the executable fat JAR produced by Spring Boot repackage plugin.
  # Exclude *-original.jar (the pre-repackage artifact) and *-exec.jar variants.
  JAR_PATH=$(find "${APP_REPO}/${MODULE}/target" -maxdepth 1 \
    -name "${MODULE}-*.jar" \
    ! -name "*-original.jar" \
    ! -name "*-exec.jar" \
    2>/dev/null | head -1)

  if [[ -z "$JAR_PATH" ]]; then
    echo "ERROR: JAR not found for module $MODULE" >&2
    echo "  Expected location: ${APP_REPO}/${MODULE}/target/${MODULE}-*.jar" >&2
    echo "  Run: ./mvnw clean install -DskipTests  (from the app repo)" >&2
    exit 1
  fi

  # ARTIFACT_NAME includes the target/ prefix so the Dockerfile COPY resolves correctly:
  # COPY ${ARTIFACT_NAME}.jar application.jar  →  COPY target/spring-petclinic-*.jar application.jar
  ARTIFACT_NAME="target/$(basename "$JAR_PATH" .jar)"
  ECR_IMAGE="${ECR_REGISTRY}/petclinic-${ENVIRONMENT}/${SERVICE}:${TAG}"

  echo "Building  : $SERVICE"
  echo "  JAR     : ${ARTIFACT_NAME}.jar"
  echo "  Image   : $ECR_IMAGE"

  docker buildx build \
    --platform linux/arm64 \
    --build-arg "ARTIFACT_NAME=${ARTIFACT_NAME}" \
    --build-arg "EXPOSED_PORT=${PORT}" \
    --tag "${ECR_IMAGE}" \
    --file "${DOCKERFILE}" \
    --provenance=false \
    --push \
    "${APP_REPO}/${MODULE}"

  PUSHED_IMAGES+=("$ECR_IMAGE")
  echo "  Pushed  : $ECR_IMAGE"
  echo ""
done

# ============================================================
# Summary
# ============================================================
echo "=== Build and Push Complete ==="
echo "Pushed ${#PUSHED_IMAGES[@]} images to ECR:"
for img in "${PUSHED_IMAGES[@]}"; do
  echo "  $img"
done
echo ""
echo "Next steps:"
echo "  1. Verify images are visible in the AWS ECR Console (eu-central-1)"
echo "  2. Update helm-values/{service}.yaml with tag: $TAG"
echo "  3. Deploy via ArgoCD or: helm upgrade --install <svc> helm/petclinic-service/ \\"
echo "       -n petclinic-${ENVIRONMENT} -f helm-values/<svc>.yaml -f helm-values/${ENVIRONMENT}.yaml \\"
echo "       --set image.tag=${TAG}"
