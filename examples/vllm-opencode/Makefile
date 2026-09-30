NAMESPACE ?= vllm
SERVICE   ?= vllm-coder-engine-service
DEPLOYMENT ?= vllm-coder-deployment-vllm
# Container port of the Service: 8000 for vLLM, 8080 for llama.cpp.
TARGET_PORT ?= 8000
PORT      ?= 8000
TOFU_DIR  ?= ../../tofu
PROMPT    ?= Write a Python function that reverses a string.
URL       := http://localhost:$(PORT)

# Read from tofu outputs unless already set in the environment.
# SERVER=llamacpp switches every target to the llama.cpp module.
SERVER    ?= vllm
ifeq ($(SERVER),llamacpp)
NAMESPACE   := llamacpp
SERVICE     := llamacpp
DEPLOYMENT  := llamacpp
TARGET_PORT := 8080
endif

VLLM_API_KEY ?= $(shell tofu -chdir=$(TOFU_DIR) output -raw $(SERVER)_api_key 2>/dev/null)
MODEL        ?= $(shell tofu -chdir=$(TOFU_DIR) output -raw $(SERVER)_served_model_name 2>/dev/null)

# Passed to the clients through the environment, never spliced into shell or
# JSON, so prompts with quotes or apostrophes work.
export VLLM_API_KEY MODEL PROMPT

.PHONY: port-forward health chat tool-call vram logs

## Forward the API to localhost:$(PORT). Keep it running in its own terminal.
## kubectl port-forward exits when a client resets a streamed request (opencode
## cancels its parallel title request), so restart it until Ctrl-C.
port-forward:
	@trap 'exit 0' INT TERM; while true; do \
	  kubectl port-forward -n $(NAMESPACE) service/$(SERVICE) $(PORT):$(TARGET_PORT); \
	  echo "port-forward exited, restarting in 1s (Ctrl-C to stop)" >&2; sleep 1; \
	done

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
	kubectl exec -n $(NAMESPACE) deploy/$(DEPLOYMENT) -- nvidia-smi

## Tail the vLLM logs; look for the KV cache size and "Application startup complete".
logs:
	kubectl logs -n $(NAMESPACE) deploy/$(DEPLOYMENT) -f --tail=200
