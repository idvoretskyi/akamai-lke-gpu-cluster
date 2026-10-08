# Envoy Gateway Module

Installs [Envoy Gateway](https://gateway.envoyproxy.io/), a
[Gateway API](https://gateway-api.sigs.k8s.io/) implementation built on Envoy,
and the `envoy` GatewayClass that KServe's Gateway uses.

## Overview

Two Helm releases:

1. `envoy-gateway` (`oci://docker.io/envoyproxy/gateway-helm`): the
   controller, plus the Gateway API CRDs and Envoy Gateway's own CRDs
   (`crds.enabled = true`), so no separate CRD install is needed.
2. `envoy-gateway-class` (the local chart in `chart/`): an `EnvoyProxy`
   with the proxy Service type and nodeSelector, and the `GatewayClass`
   pointing at it. These are custom resources, so they install after the
   controller (see `../README.md`, "Custom resources from OpenTofu").

For every `Gateway` of the class, Envoy Gateway creates an Envoy proxy
Deployment and Service in this namespace, labelled
`gateway.envoyproxy.io/owning-gateway-name=<gateway>`.

`service_type = "ClusterIP"` (default) keeps the proxy private; reach it with
`kubectl port-forward`. `LoadBalancer` provisions a public Linode
NodeBalancer.

## Usage

```hcl
module "envoy_gateway" {
  source = "./modules/envoy-gateway"

  namespace     = "envoy-gateway-system"
  chart_version = "v1.9.2"
  service_type  = "ClusterIP"
  node_selector = { "nodepool.lke/role" = "system" }
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace for the controller and the Envoy proxies | `"envoy-gateway-system"` |
| `chart_version` | gateway-helm chart version | `"v1.9.2"` |
| `gateway_class_name` | GatewayClass to create (KServe's Gateway expects `envoy`) | `"envoy"` |
| `service_type` | Envoy proxy Service type: ClusterIP, LoadBalancer, NodePort | `"ClusterIP"` |
| `node_selector` | nodeSelector for controller, certgen job and proxies | `{}` |
| `timeout` | Helm install/upgrade timeout (s) | `600` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Envoy Gateway namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `gateway_class_name` | GatewayClass name |
| `validation_commands` | Commands to validate Envoy Gateway |

## Validation

```bash
kubectl get pods -n envoy-gateway-system
kubectl get gatewayclass envoy          # ACCEPTED=True
kubectl get gateways -A                 # PROGRAMMED=True
```
