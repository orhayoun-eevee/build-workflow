# Workflow Trigger Matrix

This document defines exactly which workflow runs, when it runs, and what it is responsible for.

## build-workflow repository

| Workflow | Trigger | Automatic | Purpose |
|---|---|---|---|
| `.github/workflows/pr-required-checks.yaml` | `pull_request` to `main` (no path filter) | Yes | Single always-present required gate; conditionally runs guardrails/docker-smoke/renovate validation |
| `.github/workflows/docker-pr-smoke.yaml` | `pull_request` to `main` when `docker/**` or docker workflow files change | Yes | Smoke-build `docker/Dockerfile` before merge |
| `.github/workflows/docker-build.yaml` | `push` to `main` (docker image changes), `push` tags `v*`, `workflow_dispatch` | Yes (push/tag), Manual (`workflow_dispatch`) | Build and push `ghcr.io/<owner>/helm-validate` |
| `.github/workflows/helm-validate.yaml` | `workflow_call` only | Indirect | Reusable 5-layer Helm validation pipeline |
| `.github/workflows/release-chart.yaml` | `push` tags (`v*` or `x.y.z`), `workflow_call` | Yes (tag), Indirect | Package and publish Helm chart to GHCR OCI |
| `.github/workflows/renovate-config.yaml` | PR/push changes to Renovate config paths, `workflow_dispatch` | Yes | Validate `renovate.json` |

## Chart repositories

| Workflow | Trigger | Automatic | Purpose |
|---|---|---|---|
| `.github/workflows/on-pr.yaml` | `pull_request` to `main` | Yes | Calls reusable `build-workflow` validation (`helm-validate.yaml`) |
| `.github/workflows/on-tag.yaml` | `push` tags `v*` | Yes | Calls reusable `release-chart.yaml` |
| `.github/workflows/renovate-config.yaml` | PR/push changes to Renovate config paths, `workflow_dispatch` | Yes | Validate `renovate.json` |
| `.github/workflows/renovate-snapshot-update.yaml` | Renovate PR events + `values.yaml` changes | Yes | Regenerate and commit snapshot files for Renovate PRs |

## Docker Validation Image Lifecycle

- Image name: `ghcr.io/orhayoun-eevee/helm-validate`
- `latest` tag:
  - updated automatically on `main` pushes that affect docker image build inputs
- version tags (`vX.Y.Z`):
  - published automatically on tag pushes in `build-workflow`
- manual rebuild:
  - available via `workflow_dispatch` in `docker-build.yaml`

## Operational Notes

- Chart repos pin reusable workflows to a specific `build-workflow` commit SHA for deterministic CI.
- If reusable workflow behavior must change globally, update `build-workflow` first, then bump pinned SHAs in all chart repos.
- Snapshot-update workflows are intentionally scoped to Renovate PRs touching `values.yaml` to avoid self-mutating non-Renovate PRs.
- Branch protection for `main` should require only the `required-checks` status from `.github/workflows/pr-required-checks.yaml`.
- Do not mark path-filtered workflows as required checks; skipped path-filtered checks can block merges as pending.
