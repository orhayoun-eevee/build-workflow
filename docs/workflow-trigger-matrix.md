# Build-Workflow Trigger Matrix

Last updated: 2026-02-25
Repository: `orhayoun-eevee/build-workflow`

## Scope and terms
- **PR** = `pull_request` events targeting `main`.
- **Merge** = `push` to `main` (typically after PR merge).
- **Tag** = `push` of tags matching `v*`.
- **Reusable-only** = workflow has `on: workflow_call` and does not self-trigger from repo events.
- For many PR jobs, forks are explicitly blocked by: `github.event.pull_request.head.repo.full_name == github.repository`.

## Workflow-Level Trigger Matrix

| Workflow | PR to `main` | Merge (`push` to `main`) | New tag (`v*`) | Manual (`workflow_dispatch`) | Reusable (`workflow_call`) |
|---|---:|---:|---:|---:|---:|
| `.github/workflows/pr-required-checks.yaml` | Yes (`opened/synchronize/reopened/ready_for_review`, with `paths-ignore`) | No | No | No | No |
| `.github/workflows/quality-guardrails.yaml` | No (direct) | Yes (`paths` filtered) | No | No | Yes |
| `.github/workflows/codeql.yaml` | No (direct) | Yes (`paths` filtered) | No | No | Yes |
| `.github/workflows/dependency-review.yaml` | No (direct) | No | No | No | Yes |
| `.github/workflows/detect-required-checks-tests.yaml` | Yes (`paths` filtered) | Yes (`paths` filtered) | No | No | No |
| `.github/workflows/renovate-config.yaml` | No | Yes (`paths` filtered) | No | Yes | Yes |
| `.github/workflows/docker-build.yaml` | No | No | Yes (`tags: v*`) | Yes | No |
| `.github/workflows/helm-validate.yaml` | No (direct) | No (direct) | No (direct) | No | Yes |
| `.github/workflows/release-chart.yaml` | No (direct) | No (direct) | No (direct) | No | Yes |
| `.github/workflows/pr-required-checks-chart.yaml` | No (direct) | No (direct) | No (direct) | No | Yes |
| `.github/workflows/renovate-snapshot-update.yaml` | No (direct) | No (direct) | No (direct) | No | Yes |

## Stage/Job Conditions By Workflow

### 1) `pr-required-checks.yaml`
Why it exists: single required status (`ci-required`) with path-aware fan-out.

| Job | Runs when | Why |
|---|---|---|
| `detect-changes` | Workflow triggered and (not PR fork) | Computes booleans via `scripts/detect-required-checks.sh` to avoid unnecessary jobs. |
| `quality-guardrails` | `run_guardrails == 'true'` | Runs only when scripts/workflows/Dockerfile-related files changed (or forced on non-PR context). |
| `docker-build-smoke` | `run_docker_smoke == 'true'` | Smokes docker build only when docker/workflow pieces changed. |
| `dependency-review` | `run_dependency_review == 'true'` | Runs dependency risk gate only for dependency-relevant changes (or forced on non-PR context). |
| `renovate-config-validation` | `run_renovate_validation == 'true'` | Validates Renovate config only when Renovate files/workflow changed. |
| `codeql` | `run_codeql == 'true'` | Limits CodeQL to workflow/script changes requiring actions security scan. |
| `ci-required` | `always()` plus same-repo guard for PR | Aggregates job outcomes into one required check result. |

Notes:
- Also runs on `merge_group` (`checks_requested`) for merge queue safety.
- `paths-ignore` suppresses PR runs for docs-only/meta-only changes.
- PR fan-out is single-entry via this workflow; reusable child workflows do not self-trigger on PR.

### 2) `quality-guardrails.yaml`
Why it exists: hard policy checks for workflow hygiene and supply-chain pinning.

| Job | Runs when | Why |
|---|---|---|
| `lint-automation` | Trigger fired and (not PR fork) | Enforces shell/workflow/Dockerfile linting and guardrails (permissions, pinned actions, ref policies, etc.). |

### 3) `codeql.yaml`
Why it exists: CodeQL analysis for Actions code/scripts surface.

| Job | Runs when | Why |
|---|---|---|
| `analyze` | Trigger fired and (not PR fork) | Security scanning for workflow/script changes and weekly scheduled run. |

### 4) `dependency-review.yaml`
Why it exists: dependency risk gate on PRs.

| Job | Runs when | Why |
|---|---|---|
| `dependency-review` | Trigger fired via `workflow_call` | Invoked by orchestrator to keep PR check surface deterministic and avoid duplicate runs. |

### 5) `detect-required-checks-tests.yaml`
Why it exists: regression tests for path-detection logic.

| Job | Runs when | Why |
|---|---|---|
| `test-detect-required-checks` | Trigger fired and (not PR fork) | Validates `detect-required-checks.sh` behavior whenever detection logic/workflow wiring changes. |

### 6) `renovate-config.yaml`
Why it exists: validate Renovate configuration deterministically.

| Job | Runs when | Why |
|---|---|---|
| `validate` | Push to `main` with Renovate-path changes, or manual dispatch, or workflow_call | Ensures Renovate config remains valid/strict without spending CI on unrelated changes. |

### 7) `docker-build.yaml`
Why it exists: publish `helm-validate` tool image.

| Job | Runs when | Why |
|---|---|---|
| `build-and-push` | Tag push `v*` or manual dispatch | Release image only on explicit release signal (tag) or intentional manual run. |

### 8) Reusable-only workflows

| Workflow | Internal jobs | Effective run condition |
|---|---|---|
| `helm-validate.yaml` | `validate` | Only when called by another workflow/repo. |
| `release-chart.yaml` | `release` | Only when called; expects tag context in caller for version/tag check. |
| `pr-required-checks-chart.yaml` | `detect-changes`, `dependency-review`, `validate-*`, `renovate-config-validation`, `ci-required` | Only when chart repos call it; executes chart-specific required-check orchestration. |
| `renovate-snapshot-update.yaml` | `update-snapshots` | Only when called in PR context and actor+PR author are `renovate[bot]` from same repo. |

## PR vs Merge vs Tag: Practical Summary

| Scenario | What should run in `build-workflow` repo |
|---|---|
| Open/update PR to `main` touching workflows/scripts/docker | `pr-required-checks` only as PR entrypoint (with selective child jobs: guardrails/docker-smoke/dependency-review/renovate/codeql), plus `detect-required-checks-tests` if relevant files changed. |
| Merge PR to `main` | `quality-guardrails`, `codeql`, `detect-required-checks-tests`, `renovate-config` only if each workflow's `push.paths` match changed files. |
| Push tag like `v0.1.20` | `docker-build` only (unless manually dispatching others). |

## Best-Practice Notes For Codex Context
- Keep required PR gating centralized through `pr-required-checks.yaml` + `ci-required` aggregator.
- Keep PR execution single-entry via wrapper orchestration; avoid duplicate direct PR triggers in reusable workflows.
- Keep path-based short-circuiting in `detect-required-checks.sh`; update tests in `scripts/test-detect-required-checks.sh` when rules change.
- Avoid duplicate concurrency group names between caller and reusable workflows (deadlock risk).
- Reusable workflows should remain event-agnostic except for explicit guards needed for safety (e.g., Renovate bot checks).
- For release operations, prefer tag-driven triggers in caller repos and let reusable workflows stay `workflow_call` only.
