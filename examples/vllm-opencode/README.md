# vLLM for opencode

Uses the cluster's vLLM server (`install_vllm = true`) as the model backend
for [opencode](https://opencode.ai). The Service is ClusterIP only; the
laptop reaches it through `kubectl port-forward`, and every `/v1` request
needs the API key.

**Requires `install_vllm = true` and `install_ollama = false`** (both take
the whole GPU). `jq` and `kubectl` must be on PATH.

## What it validates

| Check | Expected |
|---|---|
| `make health` | `health: ok` and the served model id |
| `make chat` | A normal completion |
| `make tool-call` | `true` then `tool-call: ok`: a well-formed `tool_calls` entry |
| `make vram` | About 20,475 MiB total in `nvidia-smi` |
| `make logs` | The KV cache size and `Application startup complete` |

## Quick start

```bash
# tofu/tofu.tfvars
#   install_ollama = false
#   install_vllm   = true
cd tofu && tofu apply -var-file=tofu.tfvars && cd ..

# Terminal 1: forward the API to localhost:8000 (keep it running)
make -C examples/vllm-opencode port-forward

# Terminal 2 (the API key and model id are read from tofu outputs)
make -C examples/vllm-opencode health chat tool-call vram
```

The first start downloads the weights into the cache volume and captures
CUDA graphs: allow 10 to 20 minutes before the pod is Ready. Follow it with
`make -C examples/vllm-opencode logs`.

## Connect opencode

```bash
export VLLM_API_KEY="$(tofu -chdir=tofu output -raw vllm_api_key)"
cp examples/vllm-opencode/opencode.json ~/.config/opencode/opencode.json  # or merge into it
opencode -m lke-vllm/gpt-oss-20b
```

`opencode.json` defines an `@ai-sdk/openai-compatible` provider pointing at
`http://localhost:8000/v1` and reads the key from `{env:VLLM_API_KEY}`. It
never contains the key itself. The model keys match the served model names
of the presets and of the llama.cpp default, so switching servers only
changes the `-m` argument. The config has no top-level `"model"`: the
opencode schema only accepts catalogue models there, so pick the model with
`-m` or `/models`.

## Switching presets

```hcl
vllm_model_profile = "qwen3-coder-30b"  # or "gpt-oss-20b" (default)
```

`tofu apply` replaces the pod (Recreate); the new model downloads into the
same cache volume. Use `opencode -m lke-vllm/qwen3-coder-30b`.

| Preset | Model | Weights | Context |
|---|---|---|---|
| `gpt-oss-20b` | `openai/gpt-oss-20b` (MXFP4 MoE, 3.6B active) | 13.8 GB | 64K |
| `qwen3-coder-30b` | `QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` (4-bit MoE, 3.3B active) | 16.8 GB | 32K |

## Switching to llama.cpp

For GGUF models, for example dense Qwen3.8-27B:

```hcl
install_vllm     = false
install_llamacpp = true
```

Apply, then forward with
`kubectl port-forward -n llamacpp service/llamacpp 8000:8080`, export
`VLLM_API_KEY="$(tofu -chdir=tofu output -raw llamacpp_api_key)"` and run
`opencode -m lke-vllm/qwen3.8-27b`. The Makefile targets work too with
`SERVICE=llamacpp NAMESPACE=llamacpp` and matching `VLLM_API_KEY`/`MODEL`.

## Expected performance

Decode on the RTX 4000 Ada is bound by its ~360 GB/s memory bandwidth, so
speed follows the active parameters read per token:

- gpt-oss-20b and Qwen3-Coder-30B-A3B (MoE, about 3B active): roughly 50 to
  90 tokens per second single-stream.
- Dense 24B to 27B at 4-bit (llama.cpp): roughly 15 to 20 tokens per second.

Prefix caching makes repeated opencode system prompts cheap after the first
turn.

## Files

| File | Purpose |
|---|---|
| `Makefile` | port-forward, health, chat, tool-call, vram, logs |
| `opencode.json` | opencode provider config (key read from the environment) |
