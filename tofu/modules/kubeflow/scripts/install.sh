#!/usr/bin/env bash
# Installs the full Kubeflow Platform (kubeflow/community-distribution) via
# kustomize + kubectl apply --server-side. Retries on transient CRD-ordering
# failures, per upstream guidance (kubectl apply may fail until a CRD becomes
# Established; simply re-running converges).
#
# Usage: install.sh <kubeconfig-path> <git-ref> <work-dir>
set -euo pipefail

KUBECONFIG_PATH="$1"
GIT_REF="$2"
WORK_DIR="$3"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"

# Resolve to absolute paths up front — we `cd` below, and relative paths
# passed in would stop resolving correctly after that.
KUBECONFIG_PATH="$(realpath "${KUBECONFIG_PATH}")"
WORK_DIR="$(mkdir -p "${WORK_DIR}" && realpath "${WORK_DIR}")"

export KUBECONFIG="${KUBECONFIG_PATH}"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

REPO_DIR="${WORK_DIR}/community-distribution"

if [ ! -d "${REPO_DIR}" ]; then
  git clone --depth 1 --branch "${GIT_REF}" \
    https://github.com/kubeflow/community-distribution.git "${REPO_DIR}"
else
  git -C "${REPO_DIR}" fetch --depth 1 origin "${GIT_REF}"
  git -C "${REPO_DIR}" checkout "${GIT_REF}"
fi

cd "${REPO_DIR}"

max_attempts=15
attempt=1
until timeout "${TIMEOUT_SECONDS}" bash -c 'kustomize build example | kubectl apply --server-side --force-conflicts -f -'; do
  if [ "${attempt}" -ge "${max_attempts}" ]; then
    echo "kubectl apply did not converge after ${max_attempts} attempts" >&2
    exit 1
  fi
  echo "Retrying kubectl apply (attempt ${attempt}/${max_attempts})..."
  attempt=$((attempt + 1))
  sleep 20
done

echo "Kubeflow applied successfully from ref '${GIT_REF}'."
