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
opencode -m lke-vllm/qwen3-coder-30b
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
vllm_model_profile = "gpt-oss-20b"  # or "qwen3-coder-30b" (default), "qwen3-14b"
```

`tofu apply` replaces the pod (Recreate); the new model downloads into the
same cache volume. Use `opencode -m lke-vllm/gpt-oss-20b`.

| Preset | Model | Weights | Context |
|---|---|---|---|
| `qwen3-coder-30b` (default) | `QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` (4-bit MoE, 3.3B active) | 16.8 GB | 24K |
| `gpt-oss-20b` | `openai/gpt-oss-20b` (MXFP4 MoE, 3.6B active) | 13.8 GB | 64K |
| `qwen3-14b` | `Qwen/Qwen3-14B-AWQ` (official, dense) | 10 GB | 40K |

The 24K limit for Qwen3-Coder is measured: at 32K vLLM refuses to start
because the KV cache left after 16.8 GB of weights is too small. gpt-oss-20b
has the most context but, on vLLM v0.30.0, sometimes emits tool names such as
`read<|channel|>commentary` ([vllm#32587](https://github.com/vllm-project/vllm/issues/32587));
opencode rejects and retries them, so tasks take extra turns.

## Switching to llama.cpp

For GGUF models, for example dense Qwen3.8-27B:

```hcl
install_vllm     = false
install_llamacpp = true
```

Apply, then add `SERVER=llamacpp` to every target: it switches the
namespace, Service, Deployment, port (8080) and the tofu outputs used for the
key and model id.

```bash
make -C examples/vllm-opencode port-forward SERVER=llamacpp
make -C examples/vllm-opencode health chat tool-call vram SERVER=llamacpp
export VLLM_API_KEY="$(tofu -chdir=tofu output -raw llamacpp_api_key)"
opencode -m lke-vllm/qwen3.8-27b
```

## Expected performance

Decode on the RTX 4000 Ada is bound by its ~360 GB/s memory bandwidth, so
speed follows the active parameters read per token:

| Preset | Decode (measured) | opencode read, edit, run task |
|---|---|---|
| `qwen3-coder-30b` | ~113 tokens/s | 5 of 5 clean, 6 to 8 s each |
| `gpt-oss-20b` | ~80 tokens/s | 4 of 5 completed, 12 invalid tool calls in total |

Dense 24B to 27B models at 4-bit (llama.cpp) should land around 15 to 20
tokens per second (estimate, not measured).

Prefix caching makes repeated opencode system prompts cheap: a repeated
9K-token prompt went from 1.5 s to 0.14 s to first token. opencode's own
system prompt and tool definitions take a sizeable share of Qwen3-Coder's
24K window, so start a new session when long ones get close to the limit.

## Files

| File | Purpose |
|---|---|
| `Makefile` | port-forward, health, chat, tool-call, vram, logs (`SERVER=llamacpp` for llama.cpp) |
| `opencode.json` | opencode provider config (key read from the environment) |
