# AGENTS.md

OpenTofu IaC repo plus GitOps manifests and a few bash scripts, **no
application code**. The platform is one flat OpenTofu root in `tofu/`
(`platform.tf` holds every Helm release; chart values live in
`tofu/values/`). The model workload lives in `gitops/` and is applied by Argo
CD, not by OpenTofu. The CLI is `tofu` (OpenTofu >= 1.9), **not** `terraform`.
When code and prose disagree, the `.tf` files, `tofu/tofu.auto.tfvars.example`
and `gitops/` are the source of truth.

## Commands (run from `tofu/`)

- Always run `tofu fmt -recursive` before committing — CI gate
  `tofu fmt -check -recursive` fails on any unformatted file.
- CI validates with no backend and no cloud creds:
  `tofu init -backend=false` then `tofu validate -no-color`.
- Other CI gates (`.github/workflows/ci.yml`): `tflint --recursive`
  (config `tofu/.tflint.hcl`), `shellcheck` on `scripts/` and `tofu/scripts/`,
  a `gitops` job (yamllint on `gitops/`, `tofu/values/` and the local charts;
  `kubectl kustomize` on every Kustomize dir; `helm lint` + `helm template` on
  every `tofu/charts/*`, also with each `ci/*-values.yaml`), Trivy IaC scan on
  `tofu/` (fails on HIGH/CRITICAL), markdownlint on `**/*.md` (config
  `.markdownlint.json`).
- Live cluster, from the repo root: `scripts/status.sh` (health),
  `scripts/chat.sh "prompt"` (model smoke test), `scripts/ui.sh argocd|grafana|prometheus|model`.
- `scripts/gpu-test.sh` only schedules when no InferenceService holds the GPU
  (see below; README "Scheduling" says how to free it).
- There are no Makefiles. Keep it that way: a task is a short bash script in
  `scripts/` (with `set -euo pipefail`, shellcheck-clean) or part of OpenTofu.

## Local apply quirks

- Auth: the `linode` provider resolves its token from the default user in
  `~/.config/linode-cli` if present (parsed with plain HCL `file()`/`regex()`
  in `locals.tf` — deliberately not a data source, so it's never persisted to
  state), else falls back to its own `LINODE_TOKEN` environment variable
  lookup. The linode-cli config takes priority over `LINODE_TOKEN` when both
  are present. There is no tfvars entry for the token.
- `tofu apply` runs a `local-exec` that merges the kubeconfig into
  `~/.kube/config` (requires `kubectl` on PATH). Set `merge_kubeconfig = false`
  to skip (CI / externally managed kubeconfig).
- `tofu apply` does **not** wait for the model. Argo CD syncs the
  InferenceService afterwards; its first start pulls the ~7 GB vLLM image and
  ~9 GB of weights (~10 min). Check with `kubectl get isvc -n vllm`.
- Argo CD syncs `gitops_path` from `gitops_repo_url` at
  `gitops_target_revision` (default `main`), anonymously. Changes to `gitops/`
  only reach the cluster once pushed; to test a branch, set
  `gitops_target_revision` to it in `tofu.auto.tfvars`.
- Git-ignored: `*.tfvars`, `*.tfstate*`, `kubeconfig*.yaml`. `.terraform.lock.hcl`
  **is tracked** — do not gitignore it. Put real config
  in `tofu/tofu.auto.tfvars` (copy from `tofu.auto.tfvars.example`); OpenTofu
  loads `*.auto.tfvars` by itself, so no `-var-file` is needed.

## Non-obvious constraints (easy to break)

- `system_node_type` must differ from `gpu_node_type` (`variables.tf`): pool
  outputs match pools by instance type, so identical types break those outputs.
- Default `system_node_type` is `g6-standard-4` (8 GB). The platform (monitoring,
  cert-manager, Envoy Gateway, KServe, Argo CD) does not fit `g6-standard-2`.
- Cost is managed by destroying and recreating the cluster (`tofu destroy` /
  `tofu apply`). There are no suspend/resume scripts. Monitoring volumes use
  `monitoring_storage_class` = `linode-block-storage` (deleted with the PVC),
  so destroy leaves no volumes. A PVC's class is immutable: clusters created
  with the old `-retain` default must set that value or be recreated (README
  "Upgrading an existing cluster").
- Two fixed-size pools (`system`, `gpu`); autoscaling is intentionally disabled.
  The GPU pool is always tainted `nvidia.com/gpu=present:NoSchedule`; system
  workloads are pinned via `nodepool.lke/role=system` in `tofu/values/`. GPU workloads must add the matching toleration,
  a `nodepool.lke/role: gpu` selector and an `nvidia.com/gpu` limit.
- One GPU, no sharing layer: the InferenceService takes the whole card, so any
  other `nvidia.com/gpu` pod stays Pending while it runs. It uses
  `deploymentStrategy: Recreate` because a rolling update would need a second
  GPU; keep that when editing `gitops/vllm/inferenceservice.yaml`.
- KServe's chart hardcodes `gatewayClassName: envoy` for the Gateway it creates
  (`createGateway`), so the GatewayClass in `platform.tf` must stay named
  `envoy`.
- The `kserve` namespace is labelled `control-plane`; KServe's webhooks skip it,
  so InferenceServices must never go there. The model namespace is
  `local.model_namespace` (`vllm`), not a variable.
- The Hugging Face runtime's default image is CPU-only. Don't fix that with
  `huggingfaceserver.tag` in `values/kserve-runtimes.yaml`: the multinode runtime shares
  the tag and appends `-gpu` itself (`<ver>-gpu` renders `<ver>-gpu-gpu`).
  Instead the InferenceService sets `image: kserve/huggingfaceserver:<ver>-gpu`;
  keep `<ver>` in step with `chart_versions.kserve` in `locals.tf` in all three
  places: `gitops/vllm/inferenceservice.yaml` (the image) and
  `gitops/vllm/README.md` (the storage-initializer image in the gated-model
  example). KServe v0.21.0 charts are only on GHCR as `-rc1`, hence the v0.20.0
  default.
- Destroy order matters: `helm_release.applications` depends on KServe (via
  `helm_release.runtimes`) so the `vllm` Application (with Argo CD's resources
  finalizer) and its InferenceService are deleted while KServe still runs.
- The Envoy proxy Service is ClusterIP unless `gateway_service_type =
  "LoadBalancer"`. The model endpoint, Argo CD and Grafana have no
  authentication suitable for the internet: keep them behind
  `kubectl port-forward`.
- `checks.tf` uses OpenTofu `check` blocks (>= 1.9) for **non-blocking**
  advisory warnings — currently: a GPU plan not offered in the chosen region,
  and a public (LoadBalancer) Gateway. Warnings, not failures.

## GPU node image (LKE)

- LKE GPU nodes ship the NVIDIA driver, container toolkit and a containerd
  `nvidia` runtime. The GPU Operator runs with `driver.enabled: false` and
  `toolkit.enabled: false` (`values/gpu-operator.yaml`); enabling the operator's toolkit
  rewrites containerd's config and leaves the node `NotReady`. The operator's
  own device plugin is enabled and advertises `nvidia.com/gpu`.

## Layout conventions

- One flat root, no modules (they were removed: seven modules of boilerplate
  around one `helm_release` each). Add a component as a `helm_release` in
  `platform.tf` plus a file in `tofu/values/` (a `.yaml`, or `.yaml.tftpl` only
  if it needs variables). Pin it to the system pool with
  `nodepool.lke/role: system` in its values.
- Chart versions live in `local.chart_versions` (`locals.tf`). Everything people
  vary is a variable in `variables.tf`, kept to a handful; everything else is an
  opinionated default in `locals.tf`. Do not add `install_*` toggles.
- Custom resources whose CRDs are installed by the same stack (GatewayClass,
  EnvoyProxy, Argo CD Applications) go in a local chart under `tofu/charts/`,
  installed by a second `helm_release` that `depends_on` the first. Don't use
  `kubernetes_manifest` for them: it can't plan before the CRD exists, which
  breaks the first apply. Give each chart a `ci/*-values.yaml` so CI renders it
  with representative input.
- Every Helm release is `atomic = true`; timeouts are `local.helm_timeout`
  (600 s; the monitoring stack 900 s).
- `moved.tf` maps the old `module.*` addresses to the flat ones for states created
  before the refactor. Leave it until you are sure no such state remains.

## Conventions

- Single owner `@idvoretskyi` (CODEOWNERS). CI runs on PRs to `main` and on pushes to it.
- Dependabot commit prefixes: `deps(terraform)`, `deps(actions)`.
- Every commit needs a DCO `Signed-off-by` trailer (the DCO check fails the
  PR otherwise): commit with `git commit -s`, or fix a branch with
  `git rebase --signoff <base>`.
