NAMESPACE ?= ollama
SERVICE   ?= ollama
PORT      ?= 11434
MODEL     ?= gemma4:12b
PROMPT    ?= Explain in two sentences what a Kubernetes taint is.
URL       := http://localhost:$(PORT)

# Passed to the clients through the environment, never spliced into shell or
# JSON, so prompts with quotes, apostrophes or backslashes work.
export MODEL PROMPT

.PHONY: port-forward models ps chat openai pull gpu

## Forward the Ollama API to localhost:$(PORT). Keep it running in its own terminal.
port-forward:
	kubectl port-forward -n $(NAMESPACE) service/$(SERVICE) $(PORT):11434

## List downloaded models (needs port-forward).
models:
	curl -s $(URL)/api/tags | python3 -c 'import json,sys; [print(m["name"], round(m["size"]/1e9, 1), "GB") for m in json.load(sys.stdin)["models"]]'

## Show the loaded model and how much of it is on the GPU.
ps:
	kubectl exec -n $(NAMESPACE) deploy/$(SERVICE) -- ollama ps

## Chat via the native API (needs port-forward). Override MODEL= and PROMPT=.
chat:
	python3 -c 'import json,os; print(json.dumps({"model": os.environ["MODEL"], "messages": [{"role": "user", "content": os.environ["PROMPT"]}], "stream": False}))' \
	  | curl -s $(URL)/api/chat -H 'Content-Type: application/json' --data-binary @- \
	  | python3 -c 'import json,sys; print(json.load(sys.stdin)["message"]["content"])'

## Chat via the OpenAI-compatible API with a stdlib-only Python client (needs port-forward).
openai:
	OLLAMA_URL=$(URL) python3 -c 'import os,subprocess,sys; sys.exit(subprocess.call([sys.executable, "chat.py", os.environ["MODEL"], os.environ["PROMPT"]]))'

## Pull another model onto the volume, e.g. make pull MODEL=devstral-small-2:24b
pull:
	kubectl exec -n $(NAMESPACE) deploy/$(SERVICE) -- ollama pull $(MODEL)

## Show GPU memory use inside the Ollama pod.
gpu:
	kubectl exec -n $(NAMESPACE) deploy/$(SERVICE) -- nvidia-smi
