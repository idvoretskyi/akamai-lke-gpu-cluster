#!/usr/bin/env bash
# Installs the full Kubeflow Platform (kubeflow/community-distribution) via
# kustomize + kubectl apply --server-side. Retries on transient CRD-ordering
# failures, per upstream guidance (kubectl apply may fail until a CRD becomes
# Established; simply re-running converges).
#
# Usage: install.sh <kubeconfig-path> <git-ref> <work-dir>
set -euo pipefail

die() {
  echo "$1 — see modules/kubeflow/README.md prerequisites." >&2
  exit 1
}

# macOS's coreutils (`brew install coreutils`) installs GNU timeout/realpath
# under gtimeout/grealpath by default, to avoid clashing with BSD tools of
# the same name — prefer the GNU-prefixed names if that's all that's present.
resolve_cmd() {
  local preferred="$1" gnu_prefixed="$2"
  if command -v "${preferred}" >/dev/null 2>&1; then
    echo "${preferred}"
  elif command -v "${gnu_prefixed}" >/dev/null 2>&1; then
    echo "${gnu_prefixed}"
  else
    die "Required command '${preferred}' (or '${gnu_prefixed}') not found on PATH"
  fi
}

TIMEOUT_CMD="$(resolve_cmd timeout gtimeout)"
REALPATH_CMD="$(resolve_cmd realpath grealpath)"

# Fail fast with an actionable message if a required tool is missing, rather
# than burning through the ~5 minute retry loop below on every attempt only
# to discover e.g. kustomize isn't on PATH.
for cmd in git kubectl kustomize; do
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command '${cmd}' not found on PATH"
done

KUBECONFIG_PATH="$1"
GIT_REF="$2"
WORK_DIR="$3"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
# How many times to retry `kubectl apply` (per upstream's own documented
# CRD-ordering workaround) and how long to wait between attempts.
MAX_ATTEMPTS="${MAX_ATTEMPTS:-15}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-20}"

# Resolve to absolute paths up front, and create WORK_DIR — we `cd` below,
# and relative paths passed in would stop resolving correctly after that.
KUBECONFIG_PATH="$("${REALPATH_CMD}" "${KUBECONFIG_PATH}")"
mkdir -p "${WORK_DIR}"
WORK_DIR="$("${REALPATH_CMD}" "${WORK_DIR}")"

export KUBECONFIG="${KUBECONFIG_PATH}"

REPO_DIR="${WORK_DIR}/community-distribution"

if [ ! -d "${REPO_DIR}" ]; then
  git clone --depth 1 --branch "${GIT_REF}" \
    https://github.com/kubeflow/community-distribution.git "${REPO_DIR}"
else
  # A shallow `fetch <ref>` populates FETCH_HEAD but doesn't necessarily
  # create/update a local ref named ${GIT_REF} (particularly across shallow
  # fetches of different refs) -- `checkout "${GIT_REF}"` can then fail even
  # though the desired commit was fetched. Checking out FETCH_HEAD directly
  # always lands on exactly what was just fetched; the resulting detached
  # HEAD is fine here since this is a one-shot working copy, not a repo
  # anyone develops against.
  git -C "${REPO_DIR}" fetch --depth 1 origin "${GIT_REF}"
  git -C "${REPO_DIR}" checkout --detach FETCH_HEAD
fi

cd "${REPO_DIR}"

attempt=1
until "${TIMEOUT_CMD}" "${TIMEOUT_SECONDS}" bash -c 'set -o pipefail; kustomize build example | kubectl apply --server-side --force-conflicts -f -'; do
  if [ "${attempt}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "kubectl apply did not converge after ${MAX_ATTEMPTS} attempts" >&2
    exit 1
  fi
  echo "Retrying kubectl apply (attempt ${attempt}/${MAX_ATTEMPTS})..."
  attempt=$((attempt + 1))
  sleep "${RETRY_DELAY_SECONDS}"
done

echo "Kubeflow applied successfully from ref '${GIT_REF}'."
