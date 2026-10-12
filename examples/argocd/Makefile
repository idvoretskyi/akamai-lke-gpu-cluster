NAMESPACE ?= argocd
APP       ?= vllm
PORT      ?= 8081

.PHONY: password port-forward apps status refresh

## Print the initial admin password (user: admin).
password:
	@kubectl -n $(NAMESPACE) get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

## Forward the Argo CD UI to http://localhost:$(PORT). Keep this running.
port-forward:
	kubectl port-forward -n $(NAMESPACE) svc/argo-cd-argocd-server $(PORT):80

## List Applications with sync and health status.
apps:
	kubectl get applications -n $(NAMESPACE)

## Sync status, revision and managed resources of one Application.
status:
	kubectl get application $(APP) -n $(NAMESPACE) -o json \
	| jq '{sync: .status.sync.status, health: .status.health.status, revision: .status.sync.revision, source: .spec.source, resources: [.status.resources[]? | "\(.kind)/\(.name): \(.status) \(.health.status // "")"]}'

## Ask Argo CD to re-read Git now instead of waiting for the next poll (~3 min).
refresh:
	kubectl annotate application $(APP) -n $(NAMESPACE) argocd.argoproj.io/refresh=hard --overwrite
