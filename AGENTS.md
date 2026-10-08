# AGENTS.md

OpenTofu IaC repo plus GitOps manifests, **no application code**. The platform
lives in `tofu/` (root module + seven modules in `tofu/modules/`, each wrapping
Helm charts; see "Module convention" below). The model workload lives in
`gitops/` and is applied by Argo CD, not by OpenTofu. The CLI is `tofu`
(OpenTofu >= 1.9), **not** `terraform`. When code and prose disagree, the
`.tf` files, `tofu/tofu.tfvars.example` and `gitops/` are the source of truth.

## Commands (run from `tofu/`)

- Always run `tofu fmt -recursive` before committing — CI gate
  `tofu fmt -check -recursive` fails on any unformatted file.
- CI validates with no backend and no cloud creds:
  `tofu init -backend=false` then `tofu validate -no-color`.
- Modules are validated **independently** in CI. When you change
  `tofu/modules/<m>`, run `init -backend=false` + `validate` *inside that module
  dir*, not just at root.
- Other CI gates (`.github/workflows/ci.yml`): `tflint --recursive`
  (config `tofu/.tflint.hcl`, passed explicitly so modules use it too),
  `shellcheck` on `tofu/scripts/`, an `examples` job (yamllint, `py_compile`
  if any `.py` exists, JSON check, `make -n`), a `gitops` job (yamllint on
  `gitops/`, `kubectl kustomize` on every Kustomize dir, `helm lint` +
  `helm template` on every `tofu/modules/*/chart`), Trivy IaC scan on `tofu/`
  (fails on HIGH/CRITICAL), markdownlint on `**/*.md` (config
  `.markdownlint.json`).
- Model smoke test (live cluster): `make -C examples/kserve-chat wait`, then
  `make -C examples/kserve-chat port-forward` in one terminal and
  `make -C examples/kserve-chat models chat` in another.
- GitOps status: `make -C examples/argocd apps status`.
- GPU smoke test: `make -C examples/gpu-validation apply wait logs` — only
  schedules when no InferenceService holds the GPU (see below).

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
  `gitops_target_revision` to it in `tofu.tfvars`.
- Git-ignored: `*.tfvars`, `*.tfstate*`, `kubeconfig*.yaml`. `.terraform.lock.hcl`
  **is tracked** (root and each module) — do not gitignore it. Put real config
  in `tofu/tofu.tfvars` (copy from `tofu.tfvars.example`).

## Non-obvious constraints (easy to break)

- `system_node_type` must differ from `gpu_node_type` (`variables.tf`): pool
  outputs match pools by instance type, so identical types break those outputs.
- Default `system_node_type` is `g6-standard-4` (8 GB). The platform (monitoring,
  cert-manager, Envoy Gateway, KServe, Argo CD) does not fit `g6-standard-2`.
- Cost is managed by destroying and recreating the cluster (`tofu destroy` /
  `tofu apply`). There are no suspend/resume scripts. Monitoring volumes use
  `linode-block-storage` (deleted with the PVC), so destroy leaves no volumes.
- Two fixed-size pools (`system`, `gpu`); autoscaling is intentionally disabled.
  The GPU pool is tainted `nvidia.com/gpu=present:NoSchedule` when
  `dedicate_gpu_nodes = true` (default); system workloads are pinned via
  `nodepool.lke/role=system`. GPU workloads must add the matching toleration,
  a `nodepool.lke/role: gpu` selector and an `nvidia.com/gpu` limit.
- One GPU, no sharing layer: the InferenceService takes the whole card, so any
  other `nvidia.com/gpu` pod stays Pending while it runs. It uses
  `deploymentStrategy: Recreate` because a rolling update would need a second
  GPU; keep that when editing `gitops/vllm/inferenceservice.yaml`.
- KServe's chart hardcodes `gatewayClassName: envoy` for the Gateway it creates
  (`createGateway`), so the envoy-gateway module's `gateway_class_name` must
  stay `envoy`.
- The `kserve` namespace is labelled `control-plane`; KServe's webhooks skip it,
  so InferenceServices must never go there (`model_namespace` validation).
- The Hugging Face runtime's default image is CPU-only; the kserve module pins
  `kserve/huggingfaceserver:<kserve_version>-gpu`. KServe v0.21.0 charts are
  only on GHCR as `-rc1`, hence the v0.20.0 default.
- Destroy order matters: `module.argo_cd` depends on `module.kserve` so the
  `vllm` Application (with Argo CD's resources finalizer) and its
  InferenceService are deleted while KServe still runs.
- The Envoy proxy Service is ClusterIP unless `gateway_service_type =
  "LoadBalancer"`. The model endpoint, Argo CD and Grafana have no
  authentication suitable for the internet: keep them behind
  `kubectl port-forward`.
- `checks.tf` uses OpenTofu `check` blocks (>= 1.9) for **non-blocking**
  advisory warnings — currently: a GPU plan not offered in the chosen region,
  KServe without the GPU Operator, Argo CD without KServe (the bootstrap
  Application is skipped), and a public (LoadBalancer) Gateway. Warnings, not
  failures.

## GPU node image (LKE)

- LKE GPU nodes ship the NVIDIA driver, container toolkit and a containerd
  `nvidia` runtime. The GPU Operator runs with `install_driver = false` and
  `gpu_operator_install_toolkit = false`; enabling the operator's toolkit
  rewrites containerd's config and leaves the node `NotReady`. The operator's
  own device plugin is enabled and advertises `nvidia.com/gpu`.

## Module convention

- Each `tofu/modules/<name>/` wraps a Helm chart with the same layout:
  `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
  `templates/values.yaml.tftpl`, `README.md`, and a tracked
  `.terraform.lock.hcl`. New modules must mirror this and be added to the CI
  matrix in `.github/workflows/ci.yml` and to `.github/dependabot.yml`.
- Custom resources whose CRDs are installed by the same module (GatewayClass,
  EnvoyProxy, Argo CD Applications) go in a local chart under
  `modules/<name>/chart/`, installed by a second `helm_release` that
  `depends_on` the first. Don't use `kubernetes_manifest` for them: it can't
  plan before the CRD exists, which breaks the first apply.
- Every Helm release is `atomic = true`; module timeouts are 600 s (the
  monitoring stack 900 s).

## Conventions

- Single owner `@idvoretskyi` (CODEOWNERS). CI runs on PRs to `main`.
- Dependabot commit prefixes: `deps(terraform)`, `deps(actions)`.
- Every commit needs a DCO `Signed-off-by` trailer (the DCO check fails the
  PR otherwise): commit with `git commit -s`, or fix a branch with
  `git rebase --signoff <base>`.
