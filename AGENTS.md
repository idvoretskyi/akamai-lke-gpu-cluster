# AGENTS.md

OpenTofu IaC repo, **no application code**. All config lives in `tofu/` (root
module + eight modules in `tofu/modules/`, each wrapping one Helm chart; see
"Module convention" below). The CLI is `tofu` (OpenTofu >= 1.9), **not** `terraform`. When code
and prose disagree, the `.tf` files and `tofu/tofu.tfvars.example` are the
source of truth.

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
  `shellcheck` on `tofu/scripts/` and `tofu/modules/hami/scripts/`, an
  `examples` job (yamllint, `py_compile`, JSON check, `make -n`), Trivy IaC
  scan on `tofu/` (fails on HIGH/CRITICAL), markdownlint on `**/*.md`
  (config `.markdownlint.json`).
- GPU smoke test: `make -C examples/gpu-validation apply wait logs`
  (needs a live cluster with the GPU Operator running).
- Argo GPU step: `make -C examples/argo-gpu-job submit wait logs`
  (needs `install_argo_workflows = true` and HAMi).
- Ollama smoke test: `make -C examples/ollama port-forward` in one terminal,
  then `make -C examples/ollama models chat` (needs `install_ollama = true`).

## Local apply quirks

- Auth: the `linode` provider resolves its token from the default user in
  `~/.config/linode-cli` if present (parsed with plain HCL `file()`/`regex()`
  in `locals.tf` — deliberately not a data source, so it's never persisted to
  state), else falls back to its own `LINODE_TOKEN` environment variable
  lookup. The linode-cli config takes priority over `LINODE_TOKEN` when both
  are present. There is no tfvars entry for the token.
- `tofu apply` runs a `local-exec` that merges the kubeconfig into
  `~/.kube/config` (requires `kubectl` on PATH). Set `merge_kubeconfig = false`
  to skip (CI / externally managed kubeconfig). `kubectl` is also required
  whenever `install_hami = true` (default): the HAMi module restarts its
  scheduler via `modules/hami/scripts/restart-scheduler.sh`.
- The first apply with `install_ollama = true` blocks until the models are
  downloaded: the chart pulls them in a `postStart` hook, so the pod isn't
  Ready until they finish (~49 GB for the defaults). If it times out,
  re-running `tofu apply` resumes.
- Git-ignored: `*.tfvars`, `*.tfstate*`, `kubeconfig*.yaml`. `.terraform.lock.hcl`
  **is tracked** — do not gitignore it. Put real config in `tofu/tofu.tfvars`
  (copy from `tofu.tfvars.example`).

## Non-obvious constraints (easy to break)

- `system_node_type` must differ from `gpu_node_type` (`variables.tf:77`): pool
  outputs match pools by instance type, so identical types break those outputs.
- Cost is managed by destroying and recreating the cluster (`tofu destroy` /
  `tofu apply`). There are no suspend/resume scripts.
- Two fixed-size pools (`system`, `gpu`); autoscaling is intentionally disabled.
  The GPU pool is tainted `nvidia.com/gpu=present:NoSchedule` when
  `dedicate_gpu_nodes = true` (default); system workloads are pinned via
  `nodepool.lke/role=system`. GPU workloads must add the matching toleration and
  an `nvidia.com/gpu` resource limit.
- `install_opencost = true` requires `install_monitoring = true` for full
  functionality (documented in the variable description; not currently
  enforced by a `check` block).
- `install_ollama = true` (default) gives Ollama a **slice** of the GPU via
  HAMi's `nvidia.com/gpumem` (`ollama_gpu_memory_mib`, default 16000 of the
  card's 20 GB; only passed when `install_hami = true` — without HAMi that
  resource doesn't exist and the pod would never schedule). The rest is for
  plain `nvidia.com/gpu` pods, which get `hami_default_gpu_memory` (4000);
  Argo Workflow GPU steps rely on this. Setting `ollama_gpu_memory_mib` to the
  full card, or `install_hami = false`, starves other GPU pods. Its Helm
  release is deliberately **not** `atomic`, unlike the other modules: the
  first install waits for model downloads, and a rollback would delete the
  partially filled volume.
- `install_open_webui = true` (default off) needs `install_ollama`; it is
  CPU-only, on the system pool. Argo runs with `auth_mode = "server"` (no
  login), so neither UI may be exposed beyond `kubectl port-forward`.
- `checks.tf` uses OpenTofu `check` blocks (>= 1.9) for **non-blocking**
  advisory warnings — currently: a GPU plan not offered in the chosen region,
  Ollama without the GPU Operator, Ollama asking for more GPU memory than one
  card has (alone, or together with the default HAMi slice), Open WebUI without
  Ollama, and Argo plus Ollama without HAMi. Warnings, not failures.

## GPU node image (LKE)

- LKE GPU nodes ship the NVIDIA driver, container toolkit and a containerd
  `nvidia` runtime. The GPU Operator runs with `install_driver = false` and
  `gpu_operator_install_toolkit = false`; enabling the operator's toolkit
  rewrites containerd's config and leaves the node `NotReady`. HAMi therefore
  uses `runtime_class_name = "nvidia"` and `nvidia_driver_root = "/"`.

## Module convention

- Each `tofu/modules/<name>/` wraps a Helm chart with the same layout:
  `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
  `templates/values.yaml.tftpl`, `README.md`. New modules must mirror this and
  be added to the CI matrix in `.github/workflows/ci.yml` and to
  `.github/dependabot.yml`.
- `modules/ollama` defaults `timeout` to 3600 (the others use 300-900)
  because the first install waits for model downloads, and it is the one
  Helm module with `atomic = false` (see above). Both are intentional.
- Default `system_node_type` is `g6-standard-2` (4 GB), enough for the default
  stack including Argo Workflows and Open WebUI.

## Conventions

- Single owner `@idvoretskyi` (CODEOWNERS). CI runs on PRs to `main`.
- Dependabot commit prefixes: `deps(terraform)`, `deps(actions)`.
- Every commit needs a DCO `Signed-off-by` trailer (the DCO check fails the
  PR otherwise): commit with `git commit -s`, or fix a branch with
  `git rebase --signoff <base>`.
