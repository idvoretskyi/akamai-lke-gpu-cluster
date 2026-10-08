# KServe Module

Installs the [KServe](https://kserve.github.io/website/) control plane (CNCF
incubating) in Standard mode, routed through the Gateway API, with the
vLLM-backed Hugging Face serving runtime.

## Overview

Three Helm releases from `oci://ghcr.io/kserve/charts`, all at
`chart_version`:

1. `kserve-crd`: the CRDs (`InferenceService`, `ServingRuntime`, ...). A
   separate release, so the controller can be upgraded or removed without
   touching the CRDs and every InferenceService in the cluster.
2. `kserve` (`kserve-resources`): the controller and webhooks.
   - `deploymentMode: Standard`: InferenceServices become plain
     Deployments, Services and HPAs; no Knative or Istio.
   - `enableGatewayApi: true`, `createGateway: true`: the chart creates the
     shared Gateway `kserve-ingress-gateway` (class `envoy`, HTTP on port 80)
     and KServe attaches an `HTTPRoute` per InferenceService.
   - Hostnames are `<name>-<namespace>.<ingress_domain>`.
3. `kserve-runtime-configs`: the `ClusterServingRuntime`s. The Hugging Face
   runtime (vLLM) defaults to the CPU image; the module pins
   `kserve/huggingfaceserver:<chart_version>-gpu` and enlarges `/dev/shm`.

Requires cert-manager (webhook certificate) and a GatewayClass named `envoy`
(the `envoy-gateway` module). The namespace is labelled `control-plane`, which
KServe's webhooks skip: InferenceServices must live in another namespace.

KServe v0.21.0 is released, but its Helm charts are only published as
`v0.21.0-rc1` on GHCR; the default stays on v0.20.0 until they are.

## Usage

```hcl
module "kserve" {
  source = "./modules/kserve"

  namespace      = "kserve"
  chart_version  = "v0.20.0"
  ingress_domain = "kserve.local"
  node_selector  = { "nodepool.lke/role" = "system" }

  depends_on = [module.cert_manager, module.envoy_gateway]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Control-plane namespace (no InferenceServices here) | `"kserve"` |
| `chart_version` | KServe version for all three charts and the runtime image | `"v0.20.0"` |
| `ingress_domain` | Domain in InferenceService hostnames | `"kserve.local"` |
| `storage_initializer_memory_limit` | Memory limit of the storage initializer (model download) | `"4Gi"` |
| `vllm_shm_size` | `/dev/shm` size for Hugging Face runtime pods | `"2Gi"` |
| `node_selector` | nodeSelector for the controller | `{}` |
| `timeout` | Helm install/upgrade timeout per release (s) | `600` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | KServe namespace |
| `release_name` | Controller Helm release name |
| `version` | Chart version |
| `status` | Controller Helm release status |
| `gateway_name` | Shared Gateway name (`kserve-ingress-gateway`) |
| `ingress_domain` | Hostname domain |
| `validation_commands` | Commands to validate KServe |

## Validation

```bash
kubectl get pods -n kserve
kubectl get clusterservingruntimes
kubectl get gateway -n kserve kserve-ingress-gateway   # PROGRAMMED=True
kubectl get inferenceservices -A
```
