NAMESPACE ?= argo
WORKFLOW  ?= gpu-smoke
MANIFEST  ?= workflow.yaml

.PHONY: submit wait logs clean

## Submit the GPU workflow.
submit:
	kubectl apply -f $(MANIFEST)

## Wait for the workflow to succeed (up to 5 min).
wait:
	kubectl wait workflow/$(WORKFLOW) -n $(NAMESPACE) \
	  --for=jsonpath='{.status.phase}'=Succeeded \
	  --timeout=300s

## Show nvidia-smi output from the workflow's pod.
logs:
	kubectl logs -n $(NAMESPACE) -l workflows.argoproj.io/workflow=$(WORKFLOW) -c main

## Delete the workflow.
clean:
	kubectl delete workflow/$(WORKFLOW) -n $(NAMESPACE) --ignore-not-found
