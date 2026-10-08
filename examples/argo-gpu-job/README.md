# Argo Workflows GPU job

Runs `nvidia-smi` as an [Argo Workflows](https://argoproj.github.io/workflows/)
step on a HAMi vGPU slice, while Ollama keeps its own slice of the same card.

## Prerequisites

`install_argo_workflows`, `install_gpu_operator` and `install_hami` all `true`
(the defaults). If Ollama is installed it takes 16000 MiB by default; the step
gets `hami_default_gpu_memory` (4000 MiB), so both fit on the 20 GB card.

## Run

```bash
make submit wait logs
make clean
```

The `logs` target shows `nvidia-smi` reporting a ~4000 MiB device instead of the
full card.

## Argo UI

```bash
kubectl port-forward -n argo service/argo-workflows-server 2746:2746
```

Open <http://localhost:2746>. The server runs with `auth_mode = "server"`, so
there is no login; keep it behind `kubectl port-forward`.
