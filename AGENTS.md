# AGENTS.md

OpenTofu IaC repo, **no application code**. All config lives in `tofu/` (root
module + six modules in `tofu/modules/`, five wrapping Helm charts and one —
`kubeflow` — installing via kustomize/kubectl; see "Module convention"
below). The CLI is `tofu` (OpenTofu >= 1.9), **not** `terraform`. When code
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
  (config `tofu/.tflint.hcl`), `shellcheck` on `tofu/scripts/`, Trivy IaC scan on
  `tofu/` (fails on HIGH/CRITICAL), markdownlint on `**/*.md`
  (config `.markdownlint.json`).
- GPU smoke test: `make -C examples/gpu-validation apply wait logs`
  (needs a live cluster with the GPU Operator running).

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
- Git-ignored: `*.tfvars`, `*.tfstate*`, `kubeconfig*`. `.terraform.lock.hcl`
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
- `checks.tf` uses OpenTofu `check` blocks (>= 1.9) for **non-blocking**
  advisory warnings — currently: `install_kubeflow` without `install_hami`,
  and `install_kubeflow` on a system node pool too small for the measured
  ~9-10 GB usage. Warnings, not failures.

## Module convention

- Each `tofu/modules/<name>/` wraps a Helm chart with the same layout:
  `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
  `templates/values.yaml.tftpl`, `README.md`. New modules must mirror this and
  be added to the CI matrix in `.github/workflows/ci.yml` and to
  `.github/dependabot.yml`.
  - **Exception: `modules/kubeflow`.** Upstream Kubeflow has no single Helm
    chart covering the full platform (only a few individual components ship
    experimental charts) — this module installs via
    `kustomize build | kubectl apply` in a `local-exec` provisioner instead
    of `helm_release`, and has no `templates/values.yaml.tftpl`. This is
    intentional (see `modules/kubeflow/README.md`); don't "fix" it back into
    the Helm pattern.
- Default `system_node_type` is `g6-standard-2` (`variables.tf:74`);
  `g6-standard-8` is recommended only when adding Kubeflow (measured usage
  with the full stack is ~9-10 GB).

## Conventions

- Single owner `@idvoretskyi` (CODEOWNERS). CI runs on PRs to `main`.
- Dependabot commit prefixes: `deps(terraform)`, `deps(actions)`.
