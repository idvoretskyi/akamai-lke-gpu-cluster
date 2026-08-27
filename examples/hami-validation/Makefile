NAMESPACE  ?= default
MANIFEST   ?= nvidia-smi-shared-pods.yaml
POD_A      ?= hami-validation-a
POD_B      ?= hami-validation-b

.PHONY: apply wait logs clean

## Submit both GPU-sharing validation Pods.
apply:
	kubectl apply -f $(MANIFEST) -n $(NAMESPACE)

## Wait for both Pods to complete (up to 3 min each).
wait:
	kubectl wait pod/$(POD_A) -n $(NAMESPACE) \
	  --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
	kubectl wait pod/$(POD_B) -n $(NAMESPACE) \
	  --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s

## Stream logs from both Pods (each ran nvidia-smi against a GPU slice).
logs:
	kubectl logs pod/$(POD_A) -n $(NAMESPACE)
	kubectl logs pod/$(POD_B) -n $(NAMESPACE)

## Delete the completed Pods.
clean:
	kubectl delete -f $(MANIFEST) -n $(NAMESPACE) --ignore-not-found
