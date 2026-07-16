# Roboflow RF-DETR Pipeline (Kubeflow + HAMi validation)

Runs [RF-DETR](https://github.com/roboflow/rf-detr) — Roboflow's open-source,
Apache-2.0-licensed real-time object detector — as a Kubeflow Pipeline, on a
HAMi-managed GPU slice. **No Roboflow API key required**: the model class
used here (`RFDETRNano`) downloads its pretrained COCO checkpoint directly
from Roboflow's public CDN.

## What this validates

This is the most end-to-end test in the repo: Kubeflow Pipelines (Argo
Workflows) orchestrating a GPU workload, scheduled through HAMi, on a node
managed by the GPU Operator — and it validates two distinct things the
other examples (`gpu-validation`, `hami-validation`) don't.

**1. HAMi's mutating webhook correctly intercepts pods it didn't get a
manual `schedulerName` hint for.** Argo/KFP has no concept of a custom
Kubernetes scheduler to set on the pods it creates, so this component only
requests `nvidia.com/gpu: 1` — the same way any ordinary GPU workload
would. If HAMi is wired correctly, its admission webhook rewrites the pod's
`schedulerName` and `runtimeClassName` automatically. You can confirm this
happened:

```bash
POD=$(kubectl get pods -n kubeflow-user-example-com -o name | grep container-impl)
kubectl get -n kubeflow-user-example-com "$POD" \
  -o jsonpath='{.spec.schedulerName} {.spec.runtimeClassName} {.spec.nodeName}{"\n"}'
# -> hami-scheduler nvidia-legacy <gpu-node-name>
```

**2. HAMi memory *slicing* — not just GPU *count* sharing — works through
Kubeflow.** The `kfp` SDK's `set_accelerator_type()`/`set_accelerator_limit()`
only support one accelerator resource (`nvidia.com/gpu`); there's no
first-class way to also request the `nvidia.com/gpumem` resource HAMi uses
for memory slices. This component doesn't try — instead it relies on the
HAMi module's `default_gpu_memory` setting (`hami_default_gpu_memory` root
variable, default 8000 MB), a cluster-wide fallback slice size applied to
any `nvidia.com/gpu` request that doesn't specify `gpumem` explicitly. The
component asserts the GPU memory it sees matches that slice, not the whole
20 GB physical card — proving memory virtualization holds even for
orchestrators (like Kubeflow Pipelines) that have no direct way to request
it.

The component itself then confirms `torch.cuda.is_available()`, prints the
GPU name/memory it was actually given, and runs real object detection.

## Prerequisites

- `install_kubeflow = true` and `install_hami = true` (both required; see
  root `tofu.tfvars`).
- `hami_default_gpu_memory > 0` (default: `8000`) if you want the memory-slice
  assertion to mean anything — set the pipeline's `expected_gpu_memory_mib`
  parameter to `0` to skip it if you've disabled that on the HAMi side.
- Python 3.10+ locally, to run the `kfp` SDK (compiling/submitting the
  pipeline happens from your machine, not in-cluster).
- `kubectl` access to the cluster.

## Quick start

```bash
make venv                    # local virtualenv with the kfp SDK
make compile                 # sanity-check the pipeline compiles

# In one terminal:
make port-forward

# In another terminal:
make run                     # submit + block until SUCCEEDED/FAILED
```

Or, to submit without waiting and watch it yourself:

```bash
make submit
kubectl get pods -n kubeflow-user-example-com --watch
```

## Expected output

The pipeline has one GPU component (`detect-objects`). Its logs
(`kubectl logs -n kubeflow-user-example-com <container-impl-pod> -c main`)
should show:

```text
torch.cuda.is_available() = True
torch.cuda.get_device_name(0) = NVIDIA RTX 4000 Ada Generation
torch.cuda memory (total) = 8000 MiB
Confirmed HAMi vGPU memory slice: 8000 MiB (expected ~8000 MiB) — this pod did NOT get the whole physical GPU.
Detected 3 object(s): ['dog', 'person', 'car']
  - dog: 0.84
  - person: 0.77
  - car: 0.52
```

(Exact detections/confidences may vary slightly by RF-DETR version. The
memory figure will read ~20475 MiB — the whole physical GPU — if
`hami_default_gpu_memory` is set to `0`.)

First run downloads the RF-DETR checkpoint (~350 MB) inside the pod — this
happens on every fresh pod since nothing is cached between runs; expect
~1-2 minutes end-to-end, most of it PyTorch/rfdetr's own import time plus
the download.

## How the KFP → API-server auth works

Kubeflow Pipelines' multi-user mode expects an identity header
(`kubeflow-userid`, see the `pipeline-install-config` ConfigMap in the
`kubeflow` namespace) that's normally injected by the Istio/oauth2-proxy/Dex
chain when going through the dashboard. `submit.py` talks to the
`ml-pipeline` Service directly via `kubectl port-forward`, bypassing that
chain, so it sets the same header manually (defaults to the standard demo
user `user@example.com` / namespace `kubeflow-user-example-com`).

The "UI:" link `submit.py` prints after submitting points at a *separate*
port-forward of the Istio ingress gateway (`--ui-host`, defaults to
`http://localhost:8080`) — `kubectl port-forward -n istio-system
svc/istio-ingressgateway 8080:80` — since the dashboard isn't served by
`ml-pipeline` itself.

## Files

| File | Purpose |
|---|---|
| `pipeline.py` | KFP v2 pipeline definition; run directly to compile `pipeline.yaml` |
| `submit.py` | Submits the compiled pipeline to a port-forwarded KFP API server and (optionally) waits for completion. Flags: `--host` (ml-pipeline API, default `http://localhost:8888`), `--ui-host` (dashboard, default `http://localhost:8080`), `--user`, `--namespace`, `--no-wait`, `--timeout` (seconds, default 1800) |
| `Makefile` | `venv`, `compile`, `port-forward`, `submit`, `run`, `clean` |

## Cleanup

```bash
make clean
```

Deletes the completed pipeline Pods. The pipeline run record itself remains
visible in the Kubeflow dashboard (Experiments → `roboflow-rfdetr-validation`)
until the namespace/cluster is torn down.
