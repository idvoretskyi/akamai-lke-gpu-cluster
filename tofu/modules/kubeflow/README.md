# Kubeflow Platform

Installs the **full Kubeflow Platform** (Istio, Dex, Central Dashboard,
Notebooks, Katib, KServe, Pipelines, Training Operator, Profiles) from the
upstream [`kubeflow/manifests`](https://github.com/kubeflow/manifests) kustomize
distribution.

## Overview

Kubeflow has no official umbrella Helm chart, so the supported install path is
`kustomize build example | kubectl apply`, re-applied until the cluster
converges. This module runs that flow via a guarded `local-exec` provisioner
that:

1. preflights the required CLIs (`kubectl`, `kustomize`, `git`);
2. writes the cluster kubeconfig to a temporary file (never persisted);
3. clones `kubeflow/manifests` at the pinned tag;
4. applies the `example` overlay with retry/backoff until it succeeds.

### Object store: SeaweedFS (upstream default since 26.03)

Kubeflow Pipelines uses **SeaweedFS** as its S3-compatible artifact store.
Since Kubeflow manifests `26.03`, SeaweedFS is the upstream default — no custom
overlay is required. The store is exposed as `Service/seaweedfs` in the
`kubeflow` namespace.

### Scheduling on a dedicated-GPU cluster

Every Kubeflow control-plane pod runs **without** a toleration for the GPU node
taint (`nvidia.com/gpu=present:NoSchedule`), so the scheduler keeps them off the
GPU nodes and on the system pool automatically — no per-component `nodeSelector`
patching required. GPU pipeline steps opt back onto the GPU pool by adding the
matching toleration (and a GPU resource request); see
[`examples/kubeflow-pipelines`](../../../examples/kubeflow-pipelines) and
[`examples/pytorch-training`](../../../examples/pytorch-training).

## Requirements

- A reachable cluster (this module is wired to the LKE cluster's kubeconfig).
- `kubectl`, `kustomize`, and `git` on the host running `tofu apply`.
- A **large enough system pool**. The full platform needs meaningful CPU/RAM;
  use `system_node_type = "g6-standard-8"` (8 vCPU / 16 GB) or larger and set
  `system_node_count` to the desired fixed size. The root module emits an advisory check when the
  system pool looks too small.

## Usage

Enable from the root module:

```hcl
install_kubeflow           = true
kubeflow_manifests_version = "26.03"
system_node_type           = "g6-standard-8"
system_node_count          = 2
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `manifests_version` | Git tag of `kubeflow/manifests` (semver `vX.Y.Z` or CalVer `YY.MM`) | `"26.03"` |
| `kubeconfig_b64` | Base64 kubeconfig for the target cluster (sensitive) | — |
| `cluster_id` | LKE cluster ID (re-apply trigger) | — |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Primary Kubeflow namespace (`kubeflow`) |
| `version` | Installed manifests version |
| `dashboard_port_forward` | Port-forward command for the Central Dashboard |
| `default_credentials` | Default Dex static user (change it!) |
| `validation_commands` | Commands to validate the install |

## Access

```bash
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
# Open http://localhost:8080 — default user: user@example.com / 12341234
```

> **Security:** the default Dex static credentials are well-known. Change them
> (edit the `dex` config / `auth` overlay) for any non-throwaway cluster, and do
> not expose the ingress gateway publicly without authentication in front of it.

## Removal

`tofu destroy` removes Kubeflow along with the cluster. To remove Kubeflow while
keeping the cluster, run:

```bash
KF_MANIFESTS_VERSION=26.03 ./scripts/uninstall-kubeflow.sh
```

## Notes

- Install is idempotent: bumping `manifests_version` re-applies (upgrades) the
  platform in place on the next `tofu apply`.
- First install typically takes 10–20 minutes while images pull and CRDs settle.
