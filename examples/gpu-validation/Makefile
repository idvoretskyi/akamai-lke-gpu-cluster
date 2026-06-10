NAMESPACE ?= default
POD_NAME  ?= gpu-validation
MANIFEST  ?= nvidia-smi-pod.yaml

.PHONY: apply wait logs clean

## Submit the GPU validation Pod.
apply:
	kubectl apply -f $(MANIFEST) -n $(NAMESPACE)

## Wait for the Pod to complete (up to 3 min).
wait:
	kubectl wait pod/$(POD_NAME) -n $(NAMESPACE) \
	  --for=jsonpath='{.status.phase}'=Succeeded \
	  --timeout=180s

## Stream Pod logs (shows nvidia-smi output + GPU info).
logs:
	kubectl logs pod/$(POD_NAME) -n $(NAMESPACE)

## Delete the completed Pod.
clean:
	kubectl delete pod/$(POD_NAME) -n $(NAMESPACE) --ignore-not-found
