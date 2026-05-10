# Renovate Snapshot Write-Back 403 Baseline

Status: Closed for active rollout; retained as symptom baseline  
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

## 2026-05-07 Canary Follow-Up

Controlled canary PR: `jellyfin-helm#15` (`renovate/helm-dependencies`)

| Repo | PR | GitHub run ID | Observed symptom |
|------|----|---------------|------------------|
| `jellyfin-helm` | `#15` | `25493423181` | Token mint failed before checkout with HTTP `422`: the GitHub App installation did not grant the requested multi-repo token scope (`jellyfin-helm, build-workflow`) |

Paired required-check evidence on the same PR head SHA:

| Repo | PR | GitHub run ID | Observed result |
|------|----|---------------|-----------------|
| `jellyfin-helm` | `#15` | `25493423409` | `ci-required` passed on pre-write head SHA `594a69b249618f98e10193b8cb4178aee8cd7c31` |

Key log lines from run `25493423181`:

- `Failed to create token for "jellyfin-helm,build-workflow" (attempt 1): The permissions requested are not granted to this installation.`
- API status: `422`
- Workflow ref under test: `orhayoun-eevee/build-workflow/.github/workflows/renovate-snapshot-update.yaml@refs/tags/v0.1.28`

This follow-up narrows the producer-side defect: at least one current failure
mode occurs before snapshot regeneration or push-back, and it is caused by the
requested GitHub App repository scope rather than by branch write-back itself.

## 2026-05-07 Fixed-Producer Canary

Controlled canary PR: `jellyfin-helm#22` (`renovate/helm-dependencies`)

| Repo | PR | GitHub run ID | Observed symptom |
|------|----|---------------|------------------|
| `jellyfin-helm` | `#22` | `25498395519` | Token mint still failed before checkout with HTTP `422` even after narrowing the requested repo scope to `jellyfin-helm` only |

Paired required-check evidence on the same PR head SHA:

| Repo | PR | GitHub run ID | Observed result |
|------|----|---------------|-----------------|
| `jellyfin-helm` | `#22` | `25498396039` | `ci-required` passed on pre-write head SHA `58c467ebcad9f552645eadc9d245c16d4744f17a` |

Key log lines from run `25498395519`:

- `Uses: orhayoun-eevee/build-workflow/.github/workflows/renovate-snapshot-update.yaml@refs/tags/v0.1.29`
- `repositories: jellyfin-helm`
- `Failed to create token for "jellyfin-helm" (attempt 1): The permissions requested are not granted to this installation.`
- API status: `422`

This canary disproves the narrower hypothesis that multi-repo token scope was
the only defect. After `build-workflow@v0.1.29`, the active remaining blocker
is external to the repo code: the GitHub App installation used by
`GHCR_AUTO_APP_ID` does not currently grant the requested `contents: write`
token scope for `jellyfin-helm`.

## 2026-05-08 Post-Permission Canary

Controlled canary PR: `jellyfin-helm#24` (`renovate/helm-dependencies`)

| Repo | PR | GitHub run ID | Observed symptom |
|------|----|---------------|------------------|
| `jellyfin-helm` | `#24` | `25545943987` | Token mint and repo checkout succeeded, but snapshot write-back failed because the reusable workflow treated `.build-workflow/` as an unexpected non-snapshot diff |

Paired required-check evidence on the same PR head SHA:

| Repo | PR | GitHub run ID | Observed result |
|------|----|---------------|-----------------|
| `jellyfin-helm` | `#24` | `25545944131` | `ci-required` ran on head SHA `8884293c9f11dab45104f5966d5bedbfc1f55350`; the remaining failure moved out of token minting and into producer-side diff filtering |

Key log lines from run `25545943987`:

- `Created token for app installation`
- `Checked out build-workflow to .build-workflow`
- `Unexpected non-snapshot changes detected after snapshot refresh`
- `Git status:`
- `?? .build-workflow/`
- `UNEXPECTED_PATHS: .build-workflow/`
- `RESULT: unexpected-diff`
- `SNAPSHOT_CHANGE_COUNT: 0`

This canary confirms the external GitHub App permission fix worked. The active
remaining blocker moved back into repo code: `build-workflow` must ignore its
own helper checkout path when classifying unexpected mutations in the reusable
snapshot updater.

## 2026-05-08 Home Assistant Rebase Follow-Up

Refreshed Renovate PR: `home-assistant-helm#2` (`renovate/container-images`)

| Repo | PR | GitHub run ID | Observed symptom |
|------|----|---------------|------------------|
| `home-assistant-helm` | `#2` | `25548754098` | The refreshed pull request used trusted repo-local bot actor `ghcr-automation[bot]`, but the reusable workflow still skipped because its guard only allowed `renovate[bot]` |

Supporting evidence:

- PR head branch: `renovate/container-images`
- PR remained same-repo (`home-assistant-helm`)
- workflow run metadata:
  - `event: pull_request`
  - `actor: ghcr-automation[bot]`
  - `triggering_actor: ghcr-automation[bot]`
  - `head_sha: c8467fe8c8616c6c8deb735a0d635b8f037b3b2c`
- paired required-check run `25548754140` passed on the same refreshed head SHA

This follow-up narrows the next producer-side defect: the active job guard is
too strict for the trusted bot identities now used during same-repo Renovate
branch refreshes. The next hardening step must allow the known trusted bot
actor set for same-repo `renovate/*` pull requests without reopening the manual
actor path that was intentionally blocked earlier.

## 2026-05-10 Successful Active-Rollout Proof

Refreshed Renovate PR: `seerr-helm#5` (`renovate/container-images`)

| Repo | PR | GitHub run ID | Observed result |
|------|----|---------------|-----------------|
| `seerr-helm` | `#5` | `25635400442` | Snapshot write-back succeeded. The workflow started from pre-write SHA `f43b1b942b6c0554451ba21d170717ebe0148c55`, pushed commit `bc846190e2dd3716d4f4a0bf6e9056c7e250e9c8`, reported `RESULT: changed`, and changed three snapshot files. |
| `seerr-helm` | `#5` | `25635425971` | Follow-up snapshot run on the pushed SHA completed as a no-op. |

Paired required-check evidence on the final PR head SHA:

| Repo | PR | Final head SHA | Observed result |
|------|----|----------------|-----------------|
| `seerr-helm` | `#5` | `bc846190e2dd3716d4f4a0bf6e9056c7e250e9c8` | `update-snapshots`, `validate-app`, `install-smoke-app`, and `ci-required` all passed. |

This closes the active rollout blocker for same-branch GitHub Actions
write-back. The historical `403` and later `422`/guard failures remain useful
comparison baselines, but they no longer block the active `build-workflow@v0.1.32`
rollout.

## External Configuration Findings

Collected on 2026-05-07 with GitHub API and workflow evidence:

- Organization Actions secrets exist at org scope, not repo scope:
  - `GHCR_AUTO_APP_ID`
  - `GHCR_AUTO_PKEY`
  - visibility: `all`
- The GitHub App installation tied to the failing workflow includes the in-scope
  repositories. User-accessible installation repository listing for
  installation `104870162` returned:
  - `helm-common-lib`
  - `radarr-helm`
  - `build-workflow`
  - `sonarr-helm`
  - `sabnzbd-helm`
  - `transmission-helm`
  - `home-assistant-helm`
  - `ha-config`
  - `seerr-helm`
  - `jellyfin-helm`
- `jellyfin-helm` repository rulesets are currently empty.

Interpretation:

- Missing repository selection is not the current blocker.
- Missing org-level secrets are not the current blocker.
- Repository rulesets are not the current blocker in `jellyfin-helm`.
- The remaining likely blocker is GitHub App permission grant state:
  the installation can see the repo, but GitHub refuses to mint an installation
  token when `contents: write` is requested.

## Most Likely Remediation

Review the installed GitHub App under the owning account or organization and
confirm both of these conditions:

1. Under `Permissions`, the app has repository `Contents` permission set to
   `Read and write`.
2. If that permission was added or upgraded after installation, the
   installation has approved the updated permissions.

The active rollout later confirmed these conditions were remediated enough for
same-branch write-back to succeed on `seerr-helm#5`. If the app is made
read-only again, the active same-branch write-back contract in ADR-0002 cannot
succeed and must be superseded instead of widened.

## What This Confirms

- Same-branch GitHub Actions write-back was exercised in multiple app-chart
  repos.
- The active mutation contract can fail with HTTP `403` during push-back.
- Durable comparison evidence is required before final rollout documentation
  sign-off can close `G4`.

## What This Does Not Confirm

- Whether the failure was caused by branch protection, repo rulesets, app
  installation scope, token permissions, or another GitHub-side condition.
- Whether the newer canary-side `422` token-mint failure is the only remaining
  defect after producer hardening, or whether any downstream push-back `403`
  still remains once token scope is corrected.
- Whether the installed GitHub App should be granted `contents: write` on the
  affected app-chart repos, or whether the workspace should supersede
  ADR-0002's active mutation contract.
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
- Final documentation sign-off is no longer blocked by `G4`; this durable note
  now exists and links to later successful rollout evidence.
- If a canary or follow-on rollout still returns HTTP `403`, stop widening
  consumer propagation and remediate before continuing.
