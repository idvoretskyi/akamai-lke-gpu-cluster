NAMESPACE     ?= vllm
ISVC          ?= qwen3
DOMAIN        ?= kserve.local
GW_NAMESPACE  ?= envoy-gateway-system
GATEWAY       ?= kserve-ingress-gateway
PORT          ?= 8080
URL           ?= http://localhost:$(PORT)
HOST          ?= $(ISVC)-$(NAMESPACE).$(DOMAIN)
PROMPT        ?= Explain in two sentences what KServe does.

.PHONY: status wait port-forward models chat stream logs gpu

## Show the InferenceService (READY, URL) and its predictor pod.
status:
	kubectl get inferenceservice $(ISVC) -n $(NAMESPACE)
	kubectl get pods -n $(NAMESPACE) -l serving.kserve.io/inferenceservice=$(ISVC) -o wide

## Wait until the model is loaded and serving (first start: download + load).
wait:
	kubectl wait inferenceservice/$(ISVC) -n $(NAMESPACE) --for=condition=Ready --timeout=30m

## Forward the private Gateway to localhost:$(PORT). Keep this running.
port-forward:
	kubectl port-forward -n $(GW_NAMESPACE) \
	  "$$(kubectl get svc -n $(GW_NAMESPACE) -l gateway.envoyproxy.io/owning-gateway-name=$(GATEWAY) -o name)" \
	  $(PORT):80

## List models served by the InferenceService (OpenAI API).
models:
	curl -sf $(URL)/openai/v1/models -H 'Host: $(HOST)' | jq .

## One chat completion (set PROMPT=...).
chat:
	jq -n --arg m $(ISVC) --arg p "$(PROMPT)" \
	  '{model: $$m, max_tokens: 512, messages: [{role: "user", content: $$p}]}' \
	| curl -sf $(URL)/openai/v1/chat/completions -H 'Host: $(HOST)' \
	    -H 'Content-Type: application/json' -d @- \
	| jq -r '.choices[0].message.content, "-- tokens: \(.usage.prompt_tokens) in / \(.usage.completion_tokens) out"'

## Same request as chat-input.json, streamed token by token.
stream:
	jq '.stream = true' chat-input.json \
	| curl -sN $(URL)/openai/v1/chat/completions -H 'Host: $(HOST)' \
	    -H 'Content-Type: application/json' -d @-

## Tail the vLLM server logs.
logs:
	kubectl logs -n $(NAMESPACE) -l serving.kserve.io/inferenceservice=$(ISVC) -c kserve-container -f --tail=50

## GPU memory and utilisation inside the predictor pod.
gpu:
	kubectl exec -n $(NAMESPACE) deploy/$(ISVC)-predictor -c kserve-container -- nvidia-smi
