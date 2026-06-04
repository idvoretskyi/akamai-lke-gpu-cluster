#!/usr/bin/env sh
# uninstall-kubeflow.sh — Remove the Kubeflow Platform installed by
# install-kubeflow.sh, while leaving the cluster itself intact.
#
# Use this only when you want to keep the LKE cluster but drop Kubeflow.
# A full `tofu destroy` removes Kubeflow together with the cluster, so this
# script is not needed in that case.
#
# Environment variables (or pass nothing and rely on the active kubeconfig):
#   LKE_KUBECONFIG_B64    - optional base64 kubeconfig; if unset, the current
#                           KUBECONFIG / ~/.kube/config context is used
#   KF_MANIFESTS_VERSION  - git tag of kubeflow/manifests that was installed

set -eu

for bin in kubectl kustomize git base64; do
  if ! command -v "$bin" > /dev/null 2>&1; then
    echo "Error: '$bin' not found on PATH (need kubectl, kustomize, git)." >&2
    exit 1
  fi
done

: "${KF_MANIFESTS_VERSION:?KF_MANIFESTS_VERSION must be set (e.g. v1.10.0)}"

WORKDIR="$(mktemp -d)"
KUBECONFIG_FILE=""
cleanup() { rm -rf "$WORKDIR" "${KUBECONFIG_FILE:-/nonexistent}"; }
trap cleanup EXIT INT TERM

if [ -n "${LKE_KUBECONFIG_B64:-}" ]; then
  KUBECONFIG_FILE="$(mktemp)"
  printf '%s' "$LKE_KUBECONFIG_B64" | base64 -d > "$KUBECONFIG_FILE"
  chmod 600 "$KUBECONFIG_FILE"
  KUBECONFIG="$KUBECONFIG_FILE"
  export KUBECONFIG
fi

echo "Cloning kubeflow/manifests at ${KF_MANIFESTS_VERSION}…"
git clone --depth 1 --branch "${KF_MANIFESTS_VERSION}" \
  https://github.com/kubeflow/manifests.git "${WORKDIR}/manifests"

cd "${WORKDIR}/manifests"

echo "Deleting Kubeflow resources (best effort)…"
kustomize build example | kubectl delete --ignore-not-found=true -f - || true

# SeaweedFS is not part of the example kustomization; delete it explicitly.
echo "Removing SeaweedFS resources…"
kubectl delete --ignore-not-found -n kubeflow \
  deployment/seaweedfs \
  persistentvolumeclaim/seaweedfs-pvc \
  networkpolicy/seaweedfs \
  service/minio-service \
  authorizationpolicies.security.istio.io/seaweedfs-service \
  destinationrules.networking.istio.io/ml-pipeline-seaweedfs || true

echo "Kubeflow ${KF_MANIFESTS_VERSION} removed. Verify with 'kubectl get ns'."
