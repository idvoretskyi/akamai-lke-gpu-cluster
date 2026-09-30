# Ollama Example

Talks to the cluster's [Ollama](https://ollama.com/) server (installed when
`install_ollama = true`, the default) through `kubectl port-forward`. Ollama
has no authentication, so it is never exposed outside the cluster.

## Quick start

```bash
# Terminal 1: forward the API to localhost:11434 (keep it running)
make port-forward

# Terminal 2
make models                                   # downloaded models and sizes
make chat MODEL=gemma4:12b PROMPT="Hello"     # native /api/chat
make openai MODEL=gpt-oss:20b PROMPT="Hello"  # OpenAI-compatible /v1, prints tok/s
make ps                                       # loaded model, % on GPU
make gpu                                      # nvidia-smi inside the pod
```

The first request to a model loads it into VRAM, which can take up to a
minute for the larger models. Only one model is resident at a time, so
switching models triggers another load.

## Using other clients

Anything that speaks the OpenAI API works against the forwarded port:

- Base URL: `http://localhost:11434/v1`
- API key: any non-empty string

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
reply = client.chat.completions.create(
    model="qwen3.5:9b",
    messages=[{"role": "user", "content": "Hello"}],
)
print(reply.choices[0].message.content)
```

Tools that support Ollama natively (Open WebUI, Continue, Zed, the `ollama`
CLI via `OLLAMA_HOST=http://localhost:11434`) can point at the same address.

## Adding models

Pull on demand (stored on the volume, lost only if the volume is deleted):

```bash
make pull MODEL=devstral-small-2:24b
```

To make a model part of the declared set, add it to `ollama_models` in
`tofu/tofu.tfvars` and run `tofu apply`. See the fit table in
[`tofu/modules/ollama/README.md`](../../tofu/modules/ollama/README.md) —
anything much over 18 GB will spill out of the RTX 4000 Ada's 20 GB of VRAM
and run slowly.

## Files

| File | Purpose |
|---|---|
| `Makefile` | Port-forward, list, chat, pull and GPU check targets |
| `chat.py` | Stdlib-only OpenAI-compatible client; prints tokens per second |
