# Argo CD

Inspect the GitOps side of the stack: the `vllm` Application that syncs
[`gitops/vllm`](../../gitops/vllm/) (the InferenceService) into the cluster.

Needs `install_argo_cd = true`, `kubectl` and `jq`.

## Quick start

```bash
make apps            # every Application: SYNC STATUS and HEALTH
make status          # vllm: revision, source and managed resources

make password        # initial admin password
make port-forward    # UI on http://localhost:8081 (user: admin)
```

## Targets

| Target | What it does |
|---|---|
| `apps` | `kubectl get applications -n argocd` |
| `status` | sync/health, synced revision, source and resources of `APP` (default `vllm`) |
| `password` | prints the initial admin password |
| `port-forward` | Argo CD UI on `:8081` (8080 is used by the model Gateway) |
| `refresh` | hard refresh, so Argo CD re-reads Git now instead of on the next poll |

## The GitOps loop

1. Change `gitops/vllm/inferenceservice.yaml` (model, vLLM args, resources).
2. Commit and push to the branch in `gitops_target_revision` (default `main`).
3. `make refresh`, or wait ~3 minutes for the poll.
4. Argo CD applies the change; KServe recreates the predictor pod.

Automated sync uses prune and self-heal: manual `kubectl` edits to the synced
objects are reverted. Change Git instead.

After the first login, change the admin password in the UI and delete the
`argocd-initial-admin-secret` Secret.
