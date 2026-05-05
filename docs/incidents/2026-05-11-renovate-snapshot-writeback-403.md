# Renovate Snapshot Write-Back 403 Baseline

Status: Open symptom baseline  
Created: 2026-05-05  
Checkpoint due: 2026-05-11  
Scope: Same-branch `tests/snapshots/**` write-back in app-chart Renovate PRs

## Purpose

Preserve the observed HTTP `403` symptom outside transient GitHub logs so the
rollout can compare future failures against a stable baseline. This note records
observed symptoms only. It does not claim a confirmed root cause.

## Observed Runs

| Repo | GitHub run ID | Observed symptom |
|------|---------------|------------------|
| `jellyfin-helm` | `25306647440` | HTTP `403` during the workflow push-back step after snapshot refresh attempted same-branch write-back |
| `home-assistant-helm` | `25306798788` | HTTP `403` during the workflow push-back step after snapshot refresh attempted same-branch write-back |
| `seerr-helm` | `25306798936` | HTTP `403` during the workflow push-back step after snapshot refresh attempted same-branch write-back |

These run IDs came from the rollout design and ADR evidence set available on
2026-05-05. The exact root cause was still unconfirmed when this note was
created.

## What This Confirms

- Same-branch GitHub Actions write-back was exercised in multiple app-chart
  repos.
- The active mutation contract can fail with HTTP `403` during push-back.
- Durable comparison evidence is required before final rollout documentation
  sign-off can close `G4`.

## What This Does Not Confirm

- Whether the failure was caused by branch protection, repo rulesets, app
  installation scope, token permissions, or another GitHub-side condition.
- Whether later workflow hardening fully removes the symptom across all repos.
- Whether a given failed run had snapshot drift, no-op output, or another
  contributing repository state without its preserved workflow summary.

## Comparison Fields For Future Incidents

Capture these fields for any repeat failure:

- repository and PR number
- GitHub run ID
- pre-write PR head SHA
- target ref and current ref at failure time
- `build-workflow` ref or commit under test
- result (`no-op`, `changed`, `push-failed`, or `unexpected-diff`)
- snapshot diff scope and changed snapshot file count
- sanitized push stderr
- whether `ci-required` settled on the latest PR head SHA

## Current Rollout Context

- Related producer hardening baseline supplied with this rollout:
  `f8c3e95`, `e830956`
- Final documentation sign-off stays blocked by `G4` until this durable note
  exists and later rollout evidence links back to it.
- If a canary or follow-on rollout still returns HTTP `403`, stop widening
  consumer propagation and remediate before continuing.
