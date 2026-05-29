#!/usr/bin/env sh
# install-kubeflow.sh — Install the full Kubeflow Platform from the upstream
# kustomize manifests. Called by tofu/modules/kubeflow/main.tf via local-exec.
#
# Kubeflow's supported install is to apply `kustomize build example` repeatedly
# until the cluster converges (CRDs must be established before the resources
# that use them apply cleanly), so this script retries with backoff.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64    - base64-encoded kubeconfig for the target cluster
#   KF_MANIFESTS_VERSION  - git tag of kubeflow/manifests to install (vX.Y.Z)

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

echo "Applying Kubeflow manifests (full platform; this can take 10–20 minutes)…"
attempt=1
max_attempts=30
until kustomize build example | kubectl apply --server-side --force-conflicts -f -; do
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
