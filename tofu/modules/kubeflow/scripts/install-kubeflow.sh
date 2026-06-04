#!/usr/bin/env sh
# install-kubeflow.sh — Install the full Kubeflow Platform from the upstream
# kustomize manifests. Called by tofu/modules/kubeflow/main.tf via local-exec.
#
# Kubeflow's supported install is to apply `kustomize build example` repeatedly
# until the cluster converges (CRDs must be established before the resources
# that use them apply cleanly), so this script retries with backoff.
#
# Object store: SeaweedFS is always used as the S3-compatible artifact store.
# The upstream minio Deployment is removed from the generated manifests and the
# minio-service Service is repointed to SeaweedFS (same hostname/port, so all
# KFP consumers work without configuration changes). Any live minio resources
# are deleted after convergence.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64      - base64-encoded kubeconfig for the target cluster
#   KF_MANIFESTS_VERSION    - git tag of kubeflow/manifests to install (vX.Y.Z)
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
# Build a kustomize overlay that:
#   1. Replaces the upstream minio Deployment with SeaweedFS.
#      SeaweedFS exposes an S3-compatible endpoint; the existing minio-service
#      Service is repointed to it so all KFP consumers (which hardcode the
#      hostname minio-service.kubeflow:9000) continue to work unchanged.
#   2. Optionally patches every Deployment and StatefulSet in the generated
#      output to tolerate the GPU node taint.
#
# Overlay layout (all inside the cloned tree — kustomize 5.x requires resources
# to be at or below the kustomization root):
#
#   overlay/
#   ├── kustomization.yaml
#   ├── seaweedfs-noservice/          <- SeaweedFS resources (excl. Service)
#   │   ├── kustomization.yaml
#   │   ├── seaweedfs-deployment.yaml
#   │   ├── seaweedfs-pvc.yaml
#   │   ├── seadweedfs-networkpolicy.yaml
#   │   └── istio-authorization-policy.yaml
#   ├── deploy-toleration.yaml        <- (only when GPU_TOL_KEY is set)
#   └── sts-toleration.yaml           <- (only when GPU_TOL_KEY is set)
# ---------------------------------------------------------------------------
OVERLAY="${WORKDIR}/manifests/overlay"
SWFS_DIR="${OVERLAY}/seaweedfs-noservice"
mkdir -p "${OVERLAY}" "${SWFS_DIR}"

# Copy SeaweedFS manifests into the overlay tree.
# Exclude seaweedfs-service.yaml — we patch the existing minio-service instead
# to avoid a duplicate-resource conflict with the example base.
cp experimental/seaweedfs/base/seaweedfs-deployment.yaml       "${SWFS_DIR}/"
cp experimental/seaweedfs/base/seaweedfs-pvc.yaml               "${SWFS_DIR}/"
cp experimental/seaweedfs/base/seadweedfs-networkpolicy.yaml    "${SWFS_DIR}/"
cp experimental/seaweedfs/istio/istio-authorization-policy.yaml "${SWFS_DIR}/"

cat > "${SWFS_DIR}/kustomization.yaml" <<'EOF'
namespace: kubeflow
resources:
  - seaweedfs-deployment.yaml
  - seaweedfs-pvc.yaml
  - seadweedfs-networkpolicy.yaml
  - istio-authorization-policy.yaml
EOF

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
  - seaweedfs-noservice

patches:
  # -------------------------------------------------------------------------
  # Remove minio: the upstream minio Deployment is deprecated and unmaintained.
  # SeaweedFS (above) provides the S3-compatible object store instead.
  # -------------------------------------------------------------------------
  - patch: |
      \$patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: minio
        namespace: kubeflow
  - patch: |
      \$patch: delete
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: minio-pvc
        namespace: kubeflow
  - patch: |
      \$patch: delete
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      metadata:
        name: minio
        namespace: kubeflow
  - patch: |
      \$patch: delete
      apiVersion: security.istio.io/v1beta1
      kind: AuthorizationPolicy
      metadata:
        name: minio-service
        namespace: kubeflow
  - patch: |
      \$patch: delete
      apiVersion: networking.istio.io/v1alpha3
      kind: DestinationRule
      metadata:
        name: ml-pipeline-minio
        namespace: kubeflow

  # -------------------------------------------------------------------------
  # Repoint minio-service to SeaweedFS.
  # All KFP components address the object store as minio-service.kubeflow:9000;
  # we keep the Service name and port but redirect traffic to SeaweedFS port 8333.
  # -------------------------------------------------------------------------
  - target:
      kind: Service
      name: minio-service
      namespace: kubeflow
    patch: |
      - op: replace
        path: /spec/selector/app
        value: seaweedfs
      - op: remove
        path: /spec/selector/application-crd-id
      - op: replace
        path: /spec/ports/0/targetPort
        value: 8333
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
# Post-convergence cleanup: remove any live minio resources that kubectl apply
# does not prune (server-side apply only manages fields, it does not delete
# objects that are absent from the new manifest).
# ---------------------------------------------------------------------------
echo "Removing any residual minio resources from the cluster…"
kubectl delete --ignore-not-found -n kubeflow \
  deployment/minio \
  persistentvolumeclaim/minio-pvc \
  networkpolicy/minio

# Istio resources use fully-qualified group names.
kubectl delete --ignore-not-found -n kubeflow \
  authorizationpolicies.security.istio.io/minio-service \
  destinationrules.networking.istio.io/ml-pipeline-minio

# ---------------------------------------------------------------------------
# Readiness gate.
# ---------------------------------------------------------------------------
echo "Kubeflow ${KF_MANIFESTS_VERSION} applied. Waiting for the pipeline API…"
kubectl -n kubeflow rollout status deploy/ml-pipeline --timeout=600s || \
  echo "Note: ml-pipeline not ready yet; check 'kubectl get pods -n kubeflow'."

echo "Done. Access the Central Dashboard with:"
echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "  then open http://localhost:8080 (default: user@example.com / 12341234)"
