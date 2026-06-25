# Helm Chart Guide

**Last Updated:** 2026-06-24
**Purpose:** Explains the generic Helm chart structure, values file conventions, and how to deploy, modify, or extend any of the 8 Petclinic services.

## Table of Contents

1. [Overview](#overview)
2. [Chart Structure](#chart-structure)
3. [Values Hierarchy](#values-hierarchy)
4. [Deploying a Service Manually](#deploying-a-service-manually)
5. [How to Add a New Service](#how-to-add-a-new-service)
6. [How to Change Resources, Replicas, or Environment Variables](#how-to-change-resources-replicas-or-environment-variables)
7. [Conditional Resources: HPA and PDB](#conditional-resources-hpa-and-pdb)
8. [Integration with ArgoCD](#integration-with-argocd)
9. [Validation](#validation)

---

## Overview

A **single generic chart** at `helm/petclinic-service/` is shared by all 8 services. Per-service and per-environment differences are entirely in values files under `helm-values/`. The chart templates never change when adding a new service or deploying to a new environment — only the values files change.

---

## Chart Structure

```
helm/
└── petclinic-service/
    ├── Chart.yaml              # name: petclinic-service, version: 0.1.0
    ├── values.yaml             # Defaults common to all services
    └── templates/
        ├── _helpers.tpl        # Reusable label and name helpers
        ├── deployment.yaml     # Deployment (probes, resources, init containers, secrets)
        ├── service.yaml        # ClusterIP Service
        ├── configmap.yaml      # Non-secret configuration (only rendered if configData is set)
        ├── serviceaccount.yaml # ServiceAccount (annotated with IRSA role when needed)
        ├── hpa.yaml            # HPA (only rendered when autoscaling.enabled=true)
        ├── pdb.yaml            # PDB (only rendered when podDisruptionBudget.enabled=true)
        └── NOTES.txt           # Post-install summary

helm-values/
├── config-server.yaml          # Per-service: port, env vars, init containers, probes
├── discovery-server.yaml
├── api-gateway.yaml
├── customers-service.yaml
├── visits-service.yaml
├── vets-service.yaml
├── genai-service.yaml
├── admin-server.yaml
├── dev.yaml                    # Env override: registry, tag, replicas=1, HPA/PDB disabled
└── prod.yaml                   # Env override: prod registry, tag, pullPolicy
```

---

## Values Hierarchy

Helm merges values in this order — **last file wins**:

```
1. helm/petclinic-service/values.yaml   ← chart defaults (lowest priority)
2. helm-values/{service}.yaml           ← service-specific config
3. helm-values/{env}.yaml               ← environment overrides (highest priority)
```

**Example**: `customers-service` in `dev`:
- `values.yaml` sets `replicaCount: 1`, `autoscaling.enabled: false`
- `customers-service.yaml` sets `replicaCount: 2`, `autoscaling.enabled: true`, port 8081, MySQL env vars
- `dev.yaml` sets `replicaCount: 1`, `autoscaling.enabled: false` ← **wins**, so dev gets 1 replica, no HPA

This is why `dev.yaml` explicitly forces `replicaCount: 1` and `autoscaling.enabled: false` — it overrides whatever the per-service file sets for prod.

---

## Deploying a Service Manually

```bash
# Dev
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=abc1234

# Prod
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-prod \
  -f helm-values/customers-service.yaml \
  -f helm-values/prod.yaml \
  --set image.tag=abc1234
```

`--install` means "create if not exists, upgrade if it does." Always pass `--set image.tag={sha}` to pin the image.

To check what a release would produce before applying:

```bash
helm template customers-service helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml
```

---

## How to Add a New Service

1. Create `helm-values/{service-name}.yaml` with at minimum:

```yaml
image:
  name: {service-name}

service:
  port: {port}

component: service      # or gateway, server, admin
springProfiles: "docker"

configData:
  CONFIG_SERVER_URL: "http://config-server:8888"

initContainers:
  - name: wait-for-config-server
    image: busybox:1.36
    command: [sh, -c, "until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
      readOnlyRootFilesystem: true
  - name: wait-for-discovery-server
    image: busybox:1.36
    command: [sh, -c, "until wget -qO- http://discovery-server:8761/actuator/health; do sleep 5; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
      readOnlyRootFilesystem: true
```

2. Add the ECR repository to `terraform/environments/dev/main.tf` under `local.petclinic_services`.

3. Add an ArgoCD Application CRD in `k8s/argocd/applications/{env}/{service-name}.yaml` (see E-17).

No changes to the chart templates are needed.

---

## How to Change Resources, Replicas, or Environment Variables

**Change CPU/memory for one service** — edit `helm-values/{service}.yaml`:

```yaml
resources:
  requests:
    cpu: 300m
    memory: 256Mi
  limits:
    cpu: 800m
    memory: 512Mi
```

**Change prod replica count for one service** — edit `helm-values/{service}.yaml`:

```yaml
replicaCount: 3
```

`dev.yaml` overrides this back to 1 in dev, so only prod is affected.

**Add a non-secret environment variable** — add to `configData` in `helm-values/{service}.yaml`:

```yaml
configData:
  CONFIG_SERVER_URL: "http://config-server:8888"
  MY_NEW_VAR: "some-value"
```

**Add a secret-backed environment variable** — add to `env` in `helm-values/{service}.yaml`:

```yaml
env:
  - name: MY_SECRET
    valueFrom:
      secretKeyRef:
        name: my-k8s-secret    # must exist in the namespace (created by ESO)
        key: my-key
```

Never put the actual secret value in the values file. Always reference a K8s Secret synced from AWS Secrets Manager via External Secrets Operator.

---

## Conditional Resources: HPA and PDB

### HPA (Horizontal Pod Autoscaler)

HPA is only rendered when `autoscaling.enabled: true`. Set this in the per-service values file for services that need it in prod. `dev.yaml` overrides it to `false` so dev never gets HPA.

Services with HPA in prod and their limits:

| Service | minReplicas | maxReplicas | CPU Target |
|---------|-------------|-------------|------------|
| api-gateway | 2 | 6 | 70% |
| customers-service | 2 | 4 | 70% |
| visits-service | 2 | 4 | 70% |
| vets-service | 2 | 4 | 70% |
| genai-service | 1 | 3 | 70% |

### PDB (Pod Disruption Budget)

PDB is only rendered when `podDisruptionBudget.enabled: true`. Set in per-service values for services that need it.

Services with PDB in prod (all with `minAvailable: 1`):
- config-server, discovery-server, api-gateway, customers-service, visits-service, vets-service

Services without PDB: genai-service, admin-server.

---

## Integration with ArgoCD

ArgoCD (E-17) automates all Helm deployments. Each service gets an ArgoCD `Application` CRD that specifies:

```yaml
spec:
  source:
    repoURL: https://github.com/{org}/petclinic-platform.git
    path: helm/petclinic-service
    helm:
      valueFiles:
        - ../../helm-values/{service}.yaml
        - ../../helm-values/{env}.yaml
```

- **Dev**: auto-sync enabled — ArgoCD deploys immediately when `helm-values/` changes
- **Prod**: manual sync — requires explicit approval in the ArgoCD UI

CI updates `image.tag` in `helm-values/{service}.yaml` → ArgoCD detects the Git change → syncs the Helm release. GitHub Actions never runs `kubectl apply` or `helm upgrade` directly.

---

## Validation

Run the validation script to lint, template, and dry-run all 16 releases:

```bash
# All services, all environments
bash scripts/validate-helm.sh

# Single environment
bash scripts/validate-helm.sh --env dev

# Single service
bash scripts/validate-helm.sh --service customers-service

# Single service in single environment
bash scripts/validate-helm.sh --service api-gateway --env prod
```

The script runs `helm lint`, `helm template`, and `kubectl apply --dry-run=client` for each combination and reports pass/fail counts.
