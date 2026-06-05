NAMESPACE  ?= kubeflow
JOB_NAME   ?= pytorch-mnist-gpu
MANIFEST   ?= pytorch-mnist-gpu.yaml
CONTEXT    ?= $(shell kubectl config current-context)

.PHONY: apply wait status clean

## Submit the PyTorchJob to the cluster.
apply:
	kubectl apply -f $(MANIFEST) --context $(CONTEXT)

## Wait for the job to complete (polls until Succeeded or Failed).
wait:
	@echo "Waiting for PyTorchJob $(JOB_NAME) to complete…"
	@for i in $$(seq 1 60); do \
	  cond=$$(kubectl get pytorchjob $(JOB_NAME) -n $(NAMESPACE) --context $(CONTEXT) \
	    -o jsonpath='{.status.conditions[-1].type}' 2>/dev/null); \
	  phase=$$(kubectl get pod $(JOB_NAME)-master-0 -n $(NAMESPACE) --context $(CONTEXT) \
	    -o jsonpath='{.status.phase}' 2>/dev/null); \
	  echo "[$$i/60] job=$$cond  pod=$$phase"; \
	  case "$$cond" in Succeeded|Failed) break ;; esac; \
	  sleep 10; \
	done

## Show final job and pod status.
status:
	kubectl get pytorchjob $(JOB_NAME) -n $(NAMESPACE) --context $(CONTEXT) \
	  -o jsonpath='phase={.status.conditions[-1].type}{"\n"}'
	kubectl get pod $(JOB_NAME)-master-0 -n $(NAMESPACE) --context $(CONTEXT) \
	  -o jsonpath='exitCode={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}' 2>/dev/null || true

## Delete the completed job and its pods.
clean:
	kubectl delete pytorchjob $(JOB_NAME) -n $(NAMESPACE) --context $(CONTEXT) --ignore-not-found
