# Rollback Runbook

**Last Updated:** 2026-06-25
**Purpose:** Step-by-step procedures for rolling back a failed deployment in the petclinic platform. Three methods are available — use the simplest one that fits the situation.

---

## Table of Contents

1. [Method 1 — GitOps Rollback (Recommended)](#method-1--gitops-rollback-recommended)
2. [Method 2 — ArgoCD UI/CLI Rollback](#method-2--argocd-uicli-rollback)
3. [Method 3 — Emergency Kubernetes Rollback](#method-3--emergency-kubernetes-rollback)
4. [Deciding Which Method to Use](#deciding-which-method-to-use)

---

## Method 1 — GitOps Rollback (Recommended)

**When:** A bad image tag was committed to `helm-values/` and ArgoCD deployed it. You want to go back to the previous tag.
**Who:** Anyone with write access to `petclinic-platform`
**Time:** ~3 minutes

Revert the tag-update commit in Git. ArgoCD detects the revert and re-deploys the previous image.

**Steps:**

1. Find the bad commit SHA:
   ```bash
   git log --oneline helm-values/{service}.yaml
   ```

2. Revert it (creates a new commit — does not rewrite history):
   ```bash
   git revert <bad-commit-sha> --no-edit
   git push
   ```

3. ArgoCD picks up the change automatically (dev: within seconds; prod: requires manual sync approval).

**Verify:**
- `kubectl get pods -n petclinic-{env}` — pods should be restarting with the old image
- `kubectl describe pod -n petclinic-{env} <pod-name> | grep Image:` — confirm the previous SHA is running

**Rollback:**
- If the revert itself is wrong, revert the revert: `git revert HEAD --no-edit && git push`

---

## Method 2 — ArgoCD UI/CLI Rollback

**When:** You want to roll back without touching Git — e.g., the Git commit is clean but the deployed app is misbehaving.
**Who:** Anyone with ArgoCD access
**Time:** ~2 minutes

ArgoCD keeps a history of sync operations. You can roll back to a previous sync directly in the UI or CLI without modifying Git.

**Steps (UI):**

1. Open ArgoCD:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8443:443
   # then open https://localhost:8443
   ```

2. Click the affected application (e.g., `customers-service-dev`)

3. Click **History and Rollback** → select the last known good sync → click **Rollback**

**Steps (CLI):**

1. List sync history:
   ```bash
   argocd app history {service}-{env}
   ```

2. Rollback to a previous revision ID:
   ```bash
   argocd app rollback {service}-{env} <revision-id>
   ```

**Verify:**
- `argocd app get {service}-{env}` — sync status should show the previous revision
- `kubectl get pods -n petclinic-{env}` — pods running and Ready

**Important note:** ArgoCD rollback sets the app to an out-of-sync state relative to Git. The next Git commit will move it forward again. Follow up with a GitOps rollback (Method 1) to keep Git and the cluster in sync.

---

## Method 3 — Emergency Kubernetes Rollback

**When:** ArgoCD is unavailable, the cluster is on fire, and you need to roll back a single Deployment immediately.
**Who:** Anyone with `kubectl` access to the cluster
**Time:** ~1 minute

`kubectl rollout undo` reverts the Deployment to its previous ReplicaSet. This bypasses ArgoCD and Git entirely — use only as a last resort.

**Steps:**

1. Roll back the Deployment:
   ```bash
   kubectl rollout undo deployment/{service} -n petclinic-{env}
   ```

2. Watch the rollout:
   ```bash
   kubectl rollout status deployment/{service} -n petclinic-{env}
   ```

3. Confirm the previous image is running:
   ```bash
   kubectl describe deployment/{service} -n petclinic-{env} | grep Image
   ```

**Verify:**
- `kubectl get pods -n petclinic-{env}` — all pods Ready
- Application health check: `curl https://petclinic-dev.ashayelabs.xyz/actuator/health`

**Follow-up required:** After stabilising, update `helm-values/{service}.yaml` to the working image tag and push to Git. ArgoCD will then reconcile and the cluster will no longer be out of sync.

---

## Deciding Which Method to Use

| Situation | Method |
|-----------|--------|
| Bad image was built and deployed via ArgoCD | Method 1 (GitOps revert) |
| App is broken but CI/Git is fine | Method 2 (ArgoCD history) |
| ArgoCD is down or inaccessible | Method 3 (kubectl) |
| Prod service down, no time to wait for Git CI | Method 3 then follow up with Method 1 |

**Always prefer Method 1** — it keeps Git as the single source of truth and leaves ArgoCD fully in control.
