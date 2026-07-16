# HAMi GPU Virtualization Validation

Validates that [HAMi](https://github.com/Project-HAMi/HAMi) is correctly
sharing a single physical GPU across multiple Pods, by scheduling two Pods
that each request a *slice* of GPU memory (`nvidia.com/gpumem: 2000`, i.e.
2 GB) instead of the whole device.

**Requires `install_hami = true`** (the repo's lab default).

## What it validates

| Check | Expected |
|---|---|
| HAMi scheduler active | Both Pods land via `schedulerName: hami-scheduler` |
| GPU sharing works | Both Pods run concurrently on the same physical GPU |
| Memory isolation | Each Pod only sees its requested memory slice via `nvidia-smi` |
| GPU node taint tolerated | Both Pods land on the tainted GPU node |

## Quick start

```bash
make apply
make wait
make logs

# Cleanup
make clean
```

Or directly with kubectl:

```bash
kubectl apply -f nvidia-smi-shared-pods.yaml
kubectl wait pod/hami-validation-a --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl wait pod/hami-validation-b --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl logs pod/hami-validation-a
kubectl logs pod/hami-validation-b
kubectl delete -f nvidia-smi-shared-pods.yaml
```

## Confirming the slice, not just the whole GPU

`nvidia-smi` inside each Pod should report the requested memory limit
(~2 GiB), not the full physical GPU memory — confirming HAMi's virtualization
is enforcing the slice rather than merely time-sharing without limits.

To see HAMi's own view of the allocation:

```bash
kubectl get pods -n hami-system -l app.kubernetes.io/component=hami-scheduler
kubectl logs -n hami-system -l app.kubernetes.io/component=hami-scheduler | grep -i allocat
```

## Notes

- On a single-GPU lab node (`gpu_node_count = 1`), both Pods must land on the
  same physical GPU by construction. On a multi-GPU node/pool, HAMi's
  `binpack` policy (the default `scheduler_policy`) will still try to pack
  them onto the same device first.
- This example uses a bare CUDA image, not a real training/inference
  workload — see `examples/gpu-validation/` for the non-virtualized baseline.
