NAMESPACE ?= vllm
SERVICE   ?= vllm-coder-engine-service
PORT      ?= 8000
TOFU_DIR  ?= ../../tofu
PROMPT    ?= Write a Python function that reverses a string.
URL       := http://localhost:$(PORT)

# Read from tofu outputs unless already set in the environment.
VLLM_API_KEY ?= $(shell tofu -chdir=$(TOFU_DIR) output -raw vllm_api_key 2>/dev/null)
MODEL        ?= $(shell tofu -chdir=$(TOFU_DIR) output -raw vllm_served_model_name 2>/dev/null)

# Passed to the clients through the environment, never spliced into shell or
# JSON, so prompts with quotes or apostrophes work.
export VLLM_API_KEY MODEL PROMPT

.PHONY: port-forward health chat tool-call vram logs

## Forward the vLLM API to localhost:$(PORT). Keep it running in its own terminal.
port-forward:
	kubectl port-forward -n $(NAMESPACE) service/$(SERVICE) $(PORT):8000

## Check /health and list served models (needs port-forward).
health:
	curl -sf $(URL)/health && echo "health: ok"
	curl -sf $(URL)/v1/models -H "Authorization: Bearer $$VLLM_API_KEY" | jq -r '.data[].id'

## Minimal chat completion (needs port-forward). Override PROMPT=.
chat:
	jq -n '{model: env.MODEL, messages: [{role: "user", content: env.PROMPT}], max_tokens: 512}' \
	  | curl -sf $(URL)/v1/chat/completions -H "Authorization: Bearer $$VLLM_API_KEY" \
	      -H 'Content-Type: application/json' --data-binary @- \
	  | jq -r '.choices[0].message.content'

## Tool-calling check, the key test for opencode: the reply must contain a
## well-formed tool_calls entry for get_weather with a JSON "city" argument.
tool-call:
	jq -n '{model: env.MODEL, tool_choice: "auto", max_tokens: 1024, messages: [{role: "user", content: "What is the weather in Frankfurt right now? Use the tool."}], tools: [{type: "function", function: {name: "get_weather", description: "Get the current weather for a city", parameters: {type: "object", properties: {city: {type: "string"}}, required: ["city"]}}}]}' \
	  | curl -sf $(URL)/v1/chat/completions -H "Authorization: Bearer $$VLLM_API_KEY" \
	      -H 'Content-Type: application/json' --data-binary @- \
	  | jq -e '.choices[0].message.tool_calls[0] | select(.type == "function" and .function.name == "get_weather") | .function.arguments | fromjson | has("city")' \
	  && echo "tool-call: ok"

## GPU memory as seen inside the pod: expect about 20 GB total.
vram:
	kubectl exec -n $(NAMESPACE) deploy/vllm-coder-deployment-vllm -- nvidia-smi

## Tail the vLLM logs; look for the KV cache size and "Application startup complete".
logs:
	kubectl logs -n $(NAMESPACE) deploy/vllm-coder-deployment-vllm -f --tail=200
