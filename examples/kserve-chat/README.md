# KServe chat

Talk to the vLLM InferenceService (`gitops/vllm`) through the Envoy Gateway,
using the OpenAI-compatible API KServe's Hugging Face runtime exposes.

Needs `install_kserve = true`, `install_argo_cd = true` (it syncs the model),
`kubectl`, `curl` and `jq`.

## Quick start

```bash
make wait            # until READY=True (first start: image + weights, ~10 min)
make port-forward    # terminal 1: Gateway -> localhost:8080, keep running

make models          # terminal 2
make chat
make chat PROMPT="Summarise the Gateway API in one paragraph."
make stream          # chat-input.json, streamed
```

## Targets

| Target | What it does |
|---|---|
| `status` | InferenceService (READY, URL) and the predictor pod |
| `wait` | waits for `condition=Ready` (30 min timeout) |
| `port-forward` | forwards the Envoy proxy of `kserve-ingress-gateway` to `:8080` |
| `models` | `GET /openai/v1/models` |
| `chat` | one chat completion with `PROMPT`, prints the reply and token counts |
| `stream` | `chat-input.json` with `stream: true` |
| `logs` | follows the vLLM server logs |
| `gpu` | `nvidia-smi` inside the predictor pod |

## How the request is routed

```text
curl localhost:8080 ──port-forward──► Envoy proxy (ClusterIP)
   Host: qwen3-vllm.kserve.local      │ Gateway kserve/kserve-ingress-gateway
                                      ▼ HTTPRoute (created by KServe)
                              Service qwen3-predictor ──► vLLM pod on the GPU
```

The `Host` header is how the Gateway picks the InferenceService
(`<name>-<namespace>.<kserve_ingress_domain>`). Override the variables if you
changed them: `make chat NAMESPACE=... ISVC=... DOMAIN=...`.

Any OpenAI client works the same way: base URL
`http://localhost:8080/openai/v1`, model `qwen3`, any API key, plus the
`Host` header.

## Thinking mode

Qwen3 reasons in a `<think>` block before answering, which costs tokens and
time. Add `/no_think` to a prompt (as `chat-input.json` does) for a direct
answer, or raise `max_tokens` for harder questions.
