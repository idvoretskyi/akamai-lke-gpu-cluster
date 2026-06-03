#!/usr/bin/env sh
# install-kubeflow.sh — Install the full Kubeflow Platform from the upstream
# kustomize manifests. Called by tofu/modules/kubeflow/main.tf via local-exec.
#
# Kubeflow's supported install is to apply `kustomize build example` repeatedly
# until the cluster converges (CRDs must be established before the resources
# that use them apply cleanly), so this script retries with backoff.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64      - base64-encoded kubeconfig for the target cluster
#   KF_MANIFESTS_VERSION    - git tag of kubeflow/manifests to install (vX.Y.Z)
#   KF_GPU_TOLERATION_KEY   - taint key to tolerate on GPU nodes (default: nvidia.com/gpu)
#                             Set to "" to skip adding the toleration overlay.

set -eu

# Preflight: required CLIs must be on PATH. Fail with actionable guidance rather
# than an opaque "not found" mid-install.
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

# Build the kustomize target. If KF_GPU_TOLERATION_KEY is set (non-empty),
# create an overlay on top of 'example' that patches every Deployment and
# StatefulSet to tolerate the GPU node taint. This lets Kubeflow control-plane
# pods schedule onto the GPU node when the system pool has insufficient memory.
GPU_TOL_KEY="${KF_GPU_TOLERATION_KEY:-nvidia.com/gpu}"
BUILD_TARGET="example"

if [ -n "$GPU_TOL_KEY" ]; then
  echo "Creating GPU toleration overlay (key=${GPU_TOL_KEY})…"
  # Overlay must live inside the cloned tree so kustomize can use a relative
  # path to the base — kustomize 5.x rejects absolute paths in resources.
  mkdir -p "${WORKDIR}/manifests/overlay-gpu"

  # Toleration patch — applied via strategic merge to every matched resource.
  cat > "${WORKDIR}/manifests/overlay-gpu/toleration.yaml" <<EOF
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

  # Image replacements for images that are no longer available on gcr.io.
  # gcr.io/ml-pipeline/minio:RELEASE.2019-08-14T20-37-41Z-license-compliance
  # was removed from gcr.io; replace with the equivalent Docker Hub image.
  cat > "${WORKDIR}/manifests/overlay-gpu/kustomization.yaml" <<EOF
resources:
  - ../example

images:
  - name: gcr.io/ml-pipeline/minio
    newName: minio/minio
    newTag: RELEASE.2019-08-14T20-37-41Z

patches:
  - path: toleration.yaml
    target:
      kind: Deployment
  - path: toleration.yaml
    target:
      kind: StatefulSet
EOF

  BUILD_TARGET="${WORKDIR}/manifests/overlay-gpu"
fi

echo "Applying Kubeflow manifests (full platform; this can take 10–20 minutes)…"
attempt=1
max_attempts=30
until kustomize build "${BUILD_TARGET}" | kubectl apply --server-side --force-conflicts -f -; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Error: Kubeflow apply did not converge after ${max_attempts} attempts." >&2
    exit 1
  fi
  echo "Some resources are not ready yet; retrying (${attempt}/${max_attempts})…"
  attempt=$((attempt + 1))
  sleep 20
done

echo "Kubeflow ${KF_MANIFESTS_VERSION} applied. Waiting for the pipeline API…"
kubectl -n kubeflow rollout status deploy/ml-pipeline --timeout=600s || \
  echo "Note: ml-pipeline not ready yet; check 'kubectl get pods -n kubeflow'."

echo "Done. Access the Central Dashboard with:"
echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "  then open http://localhost:8080 (default: user@example.com / 12341234)"
