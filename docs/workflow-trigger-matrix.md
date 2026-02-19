# Workflow Trigger Matrix

This document defines exactly which workflow runs, when it runs, and what it is responsible for.

## build-workflow repository

| Workflow | Trigger | Automatic | Purpose |
|---|---|---|---|
| `.github/workflows/pr-required-checks.yaml` | `pull_request` to `main`, `merge_group` (`checks_requested`) | Yes | Single always-present required gate; conditionally runs guardrails/docker-smoke/renovate/codeql validation |
| `.github/workflows/docker-build.yaml` | `push` tags `v*`, `workflow_dispatch` | Yes (tag), Manual (`workflow_dispatch`) | Build and push `ghcr.io/<owner>/helm-validate` |
| `.github/workflows/helm-validate.yaml` | `workflow_call` only | Indirect | Reusable 5-layer Helm validation pipeline |
| `.github/workflows/pr-required-checks-chart.yaml` | `workflow_call` only | Indirect | Reusable always-on required gate orchestration for chart repos |
| `.github/workflows/release-chart.yaml` | `workflow_call` only | Indirect | Package and publish Helm chart to GHCR OCI |
| `.github/workflows/dependency-review.yaml` | `pull_request` to `main`, `workflow_call` | Yes (PR), Indirect (`workflow_call`) | Dependency risk policy check for dependency updates |
| `.github/workflows/codeql.yaml` | `pull_request`/`push` to `main` (`.github/workflows/**`, `scripts/**`), `schedule`, `workflow_call` | Yes (PR/push/schedule), Indirect (`workflow_call`) | Code scanning for workflow/script automation content |
| `.github/workflows/renovate-config.yaml` | push to `main` changes to Renovate config paths, `workflow_dispatch` | Yes | Validate `renovate.json` |
| `.github/workflows/quality-guardrails.yaml` | `pull_request` to `main` for automation paths, `workflow_call` | Yes (PR), Indirect (`workflow_call`) | Lint/guardrail enforcement for workflows/scripts/toolchain pins |
| `.github/workflows/renovate-snapshot-update.yaml` | `workflow_call` only | Indirect | Reusable Renovate-only snapshot refresh workflow |
| `.github/workflows/detect-required-checks-tests.yaml` | `pull_request`/`push` to `main` for detect script and workflow changes | Yes | Validates required-check path detection logic |

## App chart repositories (`radarr-helm`, `sonarr-helm`, `sabnzbd-helm`, `transmission-helm`)

| Workflow | Trigger | Automatic | Purpose |
|---|---|---|---|
| `.github/workflows/pr-required-checks.yaml` | `pull_request` to `main`, `merge_group` (`checks_requested`) | Yes | Thin wrapper calling centralized `pr-required-checks-chart.yaml` reusable orchestrator |
| `.github/workflows/on-tag.yaml` | `push` tags `v*` | Yes | Calls reusable `release-chart.yaml` |
| `.github/workflows/renovate-config.yaml` | push to `main` changes to Renovate config paths, `workflow_dispatch` | Yes | Validate `renovate.json` |
| `.github/workflows/renovate-snapshot-update.yaml` | Renovate PR events + `values.yaml` changes | Yes | Regenerate and commit snapshot files for Renovate PRs |
| `.github/workflows/codeql.yaml` | `push` to `main` (`.github/workflows/**`, `scripts/**`), `schedule`, `workflow_dispatch` | Yes | Calls centralized `build-workflow` CodeQL workflow |

## helm-common-lib repository

| Workflow | Trigger | Automatic | Purpose |
|---|---|---|---|
| `.github/workflows/pr-required-checks.yaml` | `pull_request` to `main`, `merge_group` (`checks_requested`) | Yes | Thin wrapper calling centralized `pr-required-checks-chart.yaml` reusable orchestrator |
| `.github/workflows/on-tag.yaml` | `push` tags `v*` | Yes | Calls reusable `release-chart.yaml` for `libChart` |
| `.github/workflows/renovate-config.yaml` | push to `main` changes to Renovate config paths, `workflow_dispatch` | Yes | Validate `renovate.json` |
| `.github/workflows/codeql.yaml` | `push` to `main` (`.github/workflows/**`, `scripts/**`), `schedule`, `workflow_dispatch` | Yes | Calls centralized `build-workflow` CodeQL workflow |

## Docker Validation Image Lifecycle

- Image name: `ghcr.io/orhayoun-eevee/helm-validate`
- version tags (`vX.Y.Z`):
  - published on tag pushes in `build-workflow`
  - consumed by reusable workflows using the same `vX.Y.Z` release
- manual rebuild:
  - available via `workflow_dispatch` in `docker-build.yaml`

## Operational Notes

- Chart repos pin reusable workflows to a specific `build-workflow` release tag (`vX.Y.Z`) for deterministic CI.
- Internal image/ref versions are owned by `build-workflow`; consumer repos should only bump reusable workflow tags.
- Consumers do not override `docker_image` or `build_workflow_ref`; runtime/tooling is tied to the called `build-workflow` tag.
- If reusable workflow behavior must change globally, update `build-workflow` first, then bump pinned tags in all chart repos.
- Snapshot-update workflows are intentionally scoped to Renovate PRs touching `values.yaml` to avoid self-mutating non-Renovate PRs.
- Branch protection for `main` should require only the `ci-required` status from `.github/workflows/pr-required-checks.yaml` in each repo.
- If merge queue is enabled, ensure `.github/workflows/pr-required-checks.yaml` is triggered for `merge_group` and keep only its `ci-required` status required.
- Recommended required status contexts:
  - `PR Required Checks / ci-required / ci-required (pull_request)`
  - `PR Required Checks / ci-required / ci-required (merge_group)`
- Do not mark path-filtered workflows as required checks; skipped path-filtered checks can block merges as pending.
- `release-chart.yaml` supports keyless signing/attestation (`enable_signing: true`) for published OCI chart artifacts.
