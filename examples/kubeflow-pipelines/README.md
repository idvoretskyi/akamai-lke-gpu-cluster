# Kubeflow Pipelines — demo pipelines

Two small pipelines that validate Kubeflow Pipelines on this cluster, including
the dedicated-GPU scheduling set up by the OpenTofu config.

| Pipeline | File | What it shows |
|---|---|---|
| Hello World | [`hello_pipeline.py`](hello_pipeline.py) | CPU-only 2-step pipeline; steps run on the **system pool** |
| GPU smoke test | [`gpu_pipeline.py`](gpu_pipeline.py) | A step that requests a GPU, tolerates the GPU taint, and runs `nvidia-smi` on the **dedicated GPU pool** |

The compiled IR (`hello_pipeline.yaml`, `gpu_pipeline.yaml`) is committed for
convenience — you can upload it straight to the dashboard without installing the
SDK.

## Why the GPU pipeline needs extra config

GPU nodes are tainted `nvidia.com/gpu=present:NoSchedule` so they stay reserved
for GPU work. A GPU pipeline step therefore must (see `gpu_pipeline.py`):

1. request a GPU — `task.set_accelerator_type("nvidia.com/gpu")` + `set_accelerator_limit(1)`
2. tolerate the taint — `kubernetes.add_toleration(task, key="nvidia.com/gpu", operator="Exists", effect="NoSchedule")`
3. optionally pin to the pool — `kubernetes.add_node_selector(task, "nodepool.lke/role", "gpu")`

CPU steps need none of this: without a toleration they simply can't land on the
GPU nodes, so they stay on the system pool automatically.

## Prerequisites

- Kubeflow installed on the cluster (`install_kubeflow = true`, plus
  `install_gpu_operator = true` for the GPU pipeline).
- `kubectl` pointed at the cluster (kubeconfig is auto-merged on `tofu apply`).
- For (re)compiling or submitting from Python: `make venv` (installs the KFP SDK).

## Compile

The committed `*.yaml` are already up to date. To regenerate:

```bash
make venv      # one-time: create .venv with kfp + kfp-kubernetes
make compile   # hello_pipeline.py -> hello_pipeline.yaml, etc.
```

## Run

Port-forward the Pipelines API (the dashboard's ml-pipeline service):

```bash
kubectl -n kubeflow port-forward svc/ml-pipeline-ui 8080:80
# Open http://localhost:8080 -> Pipelines -> Upload pipeline -> pick a *.yaml,
# then Create run.
```

Or submit from Python against the in-cluster API:

```bash
kubectl -n kubeflow port-forward svc/ml-pipeline 8888:8888 &
.venv/bin/python - <<'PY'
from kfp.client import Client
c = Client(host="http://localhost:8888")
run = c.create_run_from_pipeline_package(
    "gpu_pipeline.yaml",      # or hello_pipeline.yaml
    arguments={},
    run_name="gpu-smoke-test",
)
print("submitted:", run.run_id)
PY
```

> Multi-user Kubeflow runs behind Istio/Dex auth; when submitting through the
> ingress gateway you must pass an auth session cookie. Port-forwarding directly
> to the `ml-pipeline`/`ml-pipeline-ui` service (as above) is the simplest path
> for a quick smoke test.

## Verify

```bash
# The hello-world steps land on the system pool:
kubectl get pods -A -o wide | grep -E 'hello|say-hello|shout'

# The GPU step lands on a GPU node and sees the GPU:
kubectl get pods -A -o wide | grep nvidia-smi
kubectl logs <nvidia-smi-pod> -n <namespace>   # should print the GPU table
```
