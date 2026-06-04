#!/usr/bin/env sh
# install-kubeflow.sh — Install the full Kubeflow Platform from the upstream
# kustomize manifests. Called by tofu/modules/kubeflow/main.tf via local-exec.
#
# Kubeflow's supported install is to apply `kustomize build example` repeatedly
# until the cluster converges (CRDs must be established before the resources
# that use them apply cleanly), so this script retries with backoff.
#
# Object store: since kubeflow/manifests 26.03, SeaweedFS is the upstream
# default S3-compatible artifact store — no custom overlay is required. The
# upstream example ships Service/seaweedfs in the kubeflow namespace.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64      - base64-encoded kubeconfig for the target cluster
#   KF_MANIFESTS_VERSION    - git tag of kubeflow/manifests to install (vX.Y.Z
#                             or CalVer YY.MM)
#   KF_GPU_TOLERATION_KEY   - taint key to tolerate on GPU nodes.
#                             When set (non-empty), a strategic-merge patch is
#                             applied to every Deployment and StatefulSet in the
#                             generated manifests (all namespaces), allowing
#                             workloads to schedule onto tainted GPU nodes.
#                             Set to "" to disable.

set -eu

# ---------------------------------------------------------------------------
# Preflight: required CLIs must be on PATH.
# ---------------------------------------------------------------------------
for bin in kubectl kustomize git base64; do
  if ! command -v "$bin" > /dev/null 2>&1; then
    echo "Error: '$bin' not found on PATH." >&2
    echo "  Installing Kubeflow requires kubectl, kustomize, and git on the" >&2
    echo "  host running 'tofu apply'. Install the missing tool and re-run, or" >&2
    echo "  set install_kubeflow = false to skip Kubeflow." >&2
    exit 1
  fi
done

if [ -z "${LKE_KUBECONFIG_B64:-}" ] || [ -z "${KF_MANIFESTS_VERSION:-}" ]; then
  echo "Error: LKE_KUBECONFIG_B64 and KF_MANIFESTS_VERSION must be set." >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
KUBECONFIG_FILE="$(mktemp)"
cleanup() { rm -rf "$WORKDIR" "$KUBECONFIG_FILE"; }
trap cleanup EXIT INT TERM

printf '%s' "$LKE_KUBECONFIG_B64" | base64 -d > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
KUBECONFIG="$KUBECONFIG_FILE"
export KUBECONFIG

echo "Cloning kubeflow/manifests at ${KF_MANIFESTS_VERSION}…"
git clone --depth 1 --branch "${KF_MANIFESTS_VERSION}" \
  https://github.com/kubeflow/manifests.git "${WORKDIR}/manifests"

cd "${WORKDIR}/manifests"

# ---------------------------------------------------------------------------
# Build a kustomize overlay on top of the upstream example.
#
# Since kubeflow/manifests 26.03 the upstream example already includes
# SeaweedFS as the default object store; no custom patches are needed for it.
#
# The only overlay content is the optional GPU toleration patch, which adds
# a toleration for the GPU node taint to every Deployment and StatefulSet
# (across all namespaces) so Kubeflow control-plane pods can schedule onto
# tainted GPU nodes when desired.
#
# Overlay layout (inside the cloned tree — kustomize 5.x requires resources
# to be at or below the kustomization root):
#
#   overlay/
#   ├── kustomization.yaml
#   ├── deploy-toleration.yaml   <- (only when GPU_TOL_KEY is set)
#   └── sts-toleration.yaml      <- (only when GPU_TOL_KEY is set)
# ---------------------------------------------------------------------------
OVERLAY="${WORKDIR}/manifests/overlay"
mkdir -p "${OVERLAY}"

# Use no-colon default so that an explicit empty value disables tolerations.
# (The colon form — ${VAR:-default} — would override "" with the default,
#  which would incorrectly enable the overlay even when callers set VAR="".)
GPU_TOL_KEY="${KF_GPU_TOLERATION_KEY-nvidia.com/gpu}"

TOLERATION_PATCHES=""
if [ -n "${GPU_TOL_KEY}" ]; then
  echo "Creating GPU toleration patches (key=${GPU_TOL_KEY})…"

  # Kustomize strategic-merge patches must match the target resource kind.
  # Two separate files are required — one for Deployments, one for StatefulSets.
  cat > "${OVERLAY}/deploy-toleration.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder
spec:
  template:
    spec:
      tolerations:
        - key: "${GPU_TOL_KEY}"
          operator: "Exists"
          effect: "NoSchedule"
EOF

  cat > "${OVERLAY}/sts-toleration.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: placeholder
spec:
  template:
    spec:
      tolerations:
        - key: "${GPU_TOL_KEY}"
          operator: "Exists"
          effect: "NoSchedule"
EOF

  TOLERATION_PATCHES='
patches:
  - path: deploy-toleration.yaml
    target:
      kind: Deployment
  - path: sts-toleration.yaml
    target:
      kind: StatefulSet'
fi

cat > "${OVERLAY}/kustomization.yaml" <<EOF
resources:
  - ../example
${TOLERATION_PATCHES}
EOF

# ---------------------------------------------------------------------------
# Apply loop — convergence may take multiple passes as CRDs register.
# ---------------------------------------------------------------------------
echo "Applying Kubeflow manifests (full platform; this can take 10–20 minutes)…"
attempt=1
max_attempts=30
until kustomize build "${OVERLAY}" | kubectl apply --server-side --force-conflicts -f -; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Error: Kubeflow apply did not converge after ${max_attempts} attempts." >&2
    exit 1
  fi
  echo "Some resources are not ready yet; retrying (${attempt}/${max_attempts})…"
  attempt=$((attempt + 1))
  sleep 20
done

# ---------------------------------------------------------------------------
# Readiness gate.
# ---------------------------------------------------------------------------
echo "Kubeflow ${KF_MANIFESTS_VERSION} applied. Waiting for the pipeline API…"
kubectl -n kubeflow rollout status deploy/ml-pipeline --timeout=600s || \
  echo "Note: ml-pipeline not ready yet; check 'kubectl get pods -n kubeflow'."

# ---------------------------------------------------------------------------
# Trainer v2 post-install: apply ClusterTrainingRuntimes.
#
# kubeflow/manifests 26.03 ships Trainer v2 (trainer.kubeflow.org/v1alpha1)
# which requires ClusterTrainingRuntime objects (e.g. torch-distributed) to be
# present before TrainJobs can reference them. These are distributed as a
# separate kustomize overlay in the manifests tree.
# ---------------------------------------------------------------------------
RUNTIMES_OVERLAY="${WORKDIR}/manifests/applications/trainer/upstream/overlays/runtimes"
if [ -d "${RUNTIMES_OVERLAY}" ]; then
  echo "Applying ClusterTrainingRuntimes overlay…"
  kustomize build "${RUNTIMES_OVERLAY}" | kubectl apply --server-side --force-conflicts -f - || \
    echo "Warning: ClusterTrainingRuntimes overlay failed; TrainJobs may not work." >&2
else
  echo "Warning: ClusterTrainingRuntimes overlay not found at ${RUNTIMES_OVERLAY}; skipping." >&2
fi

# ---------------------------------------------------------------------------
# Networking fix: allow Kubernetes API server to reach webhook pods.
#
# The default-allow-same-namespace-kubeflow-system NetworkPolicy (applied by
# the upstream manifests) restricts ingress to kubeflow-system pods to
# same-namespace pods only. This blocks the API server (which runs on Linode
# control-plane nodes in the 192.168.128.0/17 range) from calling admission
# webhooks (jobset-controller-manager, kubeflow-trainer-controller-manager).
# Without this patch, TrainJob creation times out with "context deadline
# exceeded" even when the Linode Cloud Firewall allows the traffic.
#
# We add ipBlock rules for the Linode node CIDR and pod CIDR to the policy so
# the API server can reach webhook pods on port 9443.
# ---------------------------------------------------------------------------
echo "Patching kubeflow-system NetworkPolicy to allow API-server → webhook traffic…"
kubectl patch networkpolicy default-allow-same-namespace-kubeflow-system \
  -n kubeflow-system \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ingress","value":[{"from":[{"podSelector":{}},{"ipBlock":{"cidr":"192.168.128.0/17"}},{"ipBlock":{"cidr":"10.2.0.0/16"}}]}]}]' || \
  echo "Warning: NetworkPolicy patch failed; webhooks may not be reachable." >&2

# ---------------------------------------------------------------------------
# PodSecurity: allow GPU workloads in the kubeflow namespace.
#
# The kubeflow namespace is labeled enforce=restricted by the upstream
# manifests, which blocks GPU training pods (they run as root and need
# unrestricted capabilities). Relabel to privileged for lab use.
# ---------------------------------------------------------------------------
echo "Relabeling kubeflow namespace PodSecurity to privileged…"
kubectl label namespace kubeflow \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite || \
  echo "Warning: namespace label failed; GPU training pods may be blocked by PodSecurity." >&2

echo "Done. Access the Central Dashboard with:"
echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "  then open http://localhost:8080 (default: user@example.com / 12341234)"
