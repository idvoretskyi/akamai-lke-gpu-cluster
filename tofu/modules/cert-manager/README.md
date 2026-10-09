# cert-manager Module

Installs [cert-manager](https://cert-manager.io/) (CNCF graduated), which
KServe requires for its admission webhook certificates.

## Overview

KServe's chart ships a self-signed `Issuer` and a `Certificate` for its
webhook service. cert-manager signs it and its CA injector writes the CA
bundle into KServe's `MutatingWebhookConfiguration` and
`ValidatingWebhookConfiguration`s. Without it, the KServe controller never
becomes ready and no `InferenceService` can be created.

The chart installs and upgrades its own CRDs (`crds.enabled = true`). All
pods are pinned with `global.nodeSelector`.

## Usage

```hcl
module "cert_manager" {
  source = "./modules/cert-manager"

  namespace              = "cert-manager"
  chart_version          = "v1.21.2"
  node_selector          = { "nodepool.lke/role" = "system" }
  enable_service_monitor = true
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"cert-manager"` |
| `chart_version` | jetstack/cert-manager chart version | `"v1.21.2"` |
| `node_selector` | nodeSelector for every cert-manager pod | `{}` |
| `enable_service_monitor` | Prometheus ServiceMonitor for the controller | `false` |
| `timeout` | Helm install/upgrade timeout (s) | `600` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | cert-manager namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `validation_commands` | Commands to validate cert-manager |

## Validation

```bash
kubectl get pods -n cert-manager
kubectl get certificates -A     # kserve/serving-cert should be Ready
```
