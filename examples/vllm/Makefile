NAMESPACE  ?= vllm
SERVICE    ?= vllm-llm-engine-service
DEPLOYMENT ?= vllm-llm-deployment-vllm
PORT       ?= 8000
MODEL      ?= Qwen/Qwen3-8B-AWQ
PROMPT     ?= Explain in two sentences what a Kubernetes taint is.
URL        := http://localhost:$(PORT)

# Passed to the clients through the environment, never spliced into shell or
# JSON, so prompts with quotes, apostrophes or backslashes work.
export MODEL PROMPT

.PHONY: port-forward models chat metrics logs gpu

## Forward the vLLM API (service port 80) to localhost:$(PORT). Keep it running in its own terminal.
port-forward:
	kubectl port-forward -n $(NAMESPACE) service/$(SERVICE) $(PORT):80

## List the served model (needs port-forward).
models:
	curl -s $(URL)/v1/models | python3 -c 'import json,sys; [print(m["id"], "max_model_len=%s" % m.get("max_model_len")) for m in json.load(sys.stdin)["data"]]'

## Chat via the OpenAI-compatible API, reusing the Ollama example's stdlib client (needs port-forward).
chat:
	LLM_URL=$(URL) python3 ../ollama/chat.py "$$MODEL" "$$PROMPT"

## Show vLLM's Prometheus metrics (TTFT, throughput, KV cache usage) (needs port-forward).
metrics:
	curl -s $(URL)/metrics | grep -E '^vllm:(num_requests_(running|waiting)|kv_cache_usage_perc|gpu_cache_usage_perc|prompt_tokens_total|generation_tokens_total|time_to_first_token_seconds_(sum|count))' || true

## Follow the engine logs (model download and load progress on first start).
logs:
	kubectl logs -n $(NAMESPACE) deploy/$(DEPLOYMENT) -f

## Show GPU memory use inside the vLLM pod.
gpu:
	kubectl exec -n $(NAMESPACE) deploy/$(DEPLOYMENT) -- nvidia-smi
