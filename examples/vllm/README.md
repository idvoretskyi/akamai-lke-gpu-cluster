# vLLM Example

Talks to the cluster's [vLLM](https://docs.vllm.ai/) engine (installed when
`install_vllm = true`; off by default) through `kubectl port-forward`. No API
key is configured, so the engine is never exposed outside the cluster.

## Quick start

```bash
# Terminal 1: forward the API to localhost:8000 (keep it running)
make port-forward

# Terminal 2
make models                      # served model and its max context
make chat PROMPT="Hello"         # OpenAI-compatible /v1, prints tok/s
make metrics                     # vllm:* Prometheus metrics
make logs                        # download/load progress on first start
make gpu                         # nvidia-smi inside the pod
```

`make chat` reuses the stdlib client in [`../ollama/chat.py`](../ollama/chat.py)
with `LLM_URL=http://localhost:8000`. `MODEL` must match the root
`vllm_model` (default `Qwen/Qwen3-8B-AWQ`); vLLM serves exactly one model.

If you changed the root module's model name, override the resource names:

```bash
make port-forward SERVICE=vllm-<name>-engine-service
make gpu DEPLOYMENT=vllm-<name>-deployment-vllm
```

## Using other clients

- Base URL: `http://localhost:8000/v1`
- API key: any non-empty string

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1", api_key="none")
reply = client.chat.completions.create(
    model="Qwen/Qwen3-8B-AWQ",
    messages=[{"role": "user", "content": "Hello"}],
)
print(reply.choices[0].message.content)
```

## Metrics in Grafana

With `install_monitoring = true` the module creates a `ServiceMonitor`, so
Prometheus scrapes the engine. Query `vllm:num_requests_running`,
`vllm:time_to_first_token_seconds_bucket` or the KV cache usage gauge in
Grafana's Explore view.
