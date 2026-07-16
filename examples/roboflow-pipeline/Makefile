KUBEFLOW_NAMESPACE ?= kubeflow-user-example-com
KUBEFLOW_USER      ?= user@example.com
LOCAL_PORT         ?= 8888
VENV               ?= .venv

.PHONY: venv port-forward compile submit run stop-port-forward clean

## Create a local virtualenv with the kfp SDK.
venv:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q --upgrade pip
	$(VENV)/bin/pip install -q kfp kfp-kubernetes

## Port-forward the Kubeflow Pipelines API server to localhost.
## Run this in a separate terminal (or background it yourself) before
## `make submit`/`make run`.
port-forward:
	kubectl port-forward -n kubeflow svc/ml-pipeline $(LOCAL_PORT):$(LOCAL_PORT)

## Compile the pipeline to pipeline.yaml (sanity-checks the pipeline
## definition without needing a live cluster).
compile:
	$(VENV)/bin/python pipeline.py

## Submit the pipeline and exit immediately (check progress in the
## Kubeflow dashboard, or with `kubectl get pods -n $(KUBEFLOW_NAMESPACE)`).
submit:
	$(VENV)/bin/python submit.py \
	  --host http://localhost:$(LOCAL_PORT) \
	  --user $(KUBEFLOW_USER) \
	  --namespace $(KUBEFLOW_NAMESPACE) \
	  --no-wait

## Submit the pipeline and block until it succeeds or fails (requires
## `make port-forward` running in another terminal).
run:
	$(VENV)/bin/python submit.py \
	  --host http://localhost:$(LOCAL_PORT) \
	  --user $(KUBEFLOW_USER) \
	  --namespace $(KUBEFLOW_NAMESPACE)

## Remove the completed pipeline Pods from the namespace.
clean:
	kubectl delete pods -n $(KUBEFLOW_NAMESPACE) -l pipeline/runid --ignore-not-found
