# gitops/vllm

The model workload, synced by the Argo CD Application `vllm` that OpenTofu
bootstraps (`tofu/modules.tf`, module `argo_cd`). Argo CD deploys it into the
`model_namespace` (default `vllm`) with automated prune and self-heal, so
`kubectl edit` changes are reverted: change things here and push.

| File | What |
|---|---|
| `inferenceservice.yaml` | KServe `InferenceService` `qwen3`: Hugging Face runtime (vLLM) on the GPU pool |
| `kustomization.yaml` | Kustomize entry point Argo CD renders |

## The InferenceService

- `storageUri: hf://Qwen/Qwen3-8B-FP8`: KServe's storage initializer
  downloads the weights into the pod before vLLM starts.
- `--model_name=qwen3`: the name used in OpenAI requests (`"model": "qwen3"`).
- `--max-model-len=32768`, `--gpu-memory-utilization=0.90`: vLLM takes 90%
  of the 20 GB card; the FP8 weights use ~9 GB and the KV cache the rest.
- `minReplicas: 1`, `maxReplicas: 1`, `deploymentStrategy: Recreate`: one
  GPU, so no scale-out and no rolling update (the new pod could never get a
  GPU while the old one holds it).
- `nodeSelector` + toleration: lands on the tainted GPU pool.

## Swapping the model

Edit `storageUri` and `args`, commit, push. Models that fit one RTX 4000 Ada
(20 GB) with vLLM:

| Model | Weights | Notes |
|---|---|---|
| `Qwen/Qwen3-8B-FP8` | ~9 GB | default, 32k context |
| `Qwen/Qwen3-4B-FP8` | ~5 GB | fastest startup |
| `Qwen/Qwen3-14B-FP8` | ~16 GB | set `--max-model-len=8192` |
| `mistralai/Ministral-8B-Instruct-2410` | ~16 GB (BF16) | set `--max-model-len=8192` |

BF16 models above ~9B parameters (e.g. `Qwen/Qwen3.5-9B`, ~19 GB) do not fit.

## Gated models

Llama, Gemma and similar need a Hugging Face token. The weights are fetched by
KServe's storage initializer (an init container), so the token goes to that
container through a `ClusterStorageContainer`, as in the
[KServe docs](https://kserve.github.io/website/docs/getting-started/genai-first-isvc).
Create the secret once, outside Git:

```bash
kubectl create secret generic hf-secret -n vllm --from-literal=HF_TOKEN=hf_xxx
```

and add a `ClusterStorageContainer` for `hf://` URIs to this directory (and to
`kustomization.yaml`):

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: ClusterStorageContainer
metadata:
  name: hf-hub
spec:
  container:
    name: storage-initializer
    image: kserve/storage-initializer:v0.20.0
    env:
      - name: HF_TOKEN
        valueFrom:
          secretKeyRef:
            name: hf-secret   # resolved in the InferenceService's namespace
            key: HF_TOKEN
    # Match the kserve module's storage_initializer_memory_limit: 1Gi is
    # OOM-killed downloading multi-GB checkpoints.
    resources:
      requests: {cpu: 100m, memory: 512Mi}
      limits: {cpu: "1", memory: 4Gi}
  supportedUriFormats:
    - prefix: hf://
```

For a token managed in Git, use an encrypted-secrets tool such as Sealed
Secrets or External Secrets instead of a plain Secret.
