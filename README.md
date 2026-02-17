# build-workflow

Centralized, reusable GitHub Actions workflows and validation scripts for Helm chart repositories.

## Overview

This repository provides:
- **Reusable GitHub Actions workflows** for PR validation and chart publishing
- **Helm Validation Framework** - 5-layer validation pipeline with strict enforcement
- **Docker image** with all validation tools pinned to exact versions
- **Configuration defaults** for yamllint, chart-testing, kube-linter, and Chart.yaml schema

## Workflow Trigger Matrix

See `docs/workflow-trigger-matrix.md` for a clear map of:
- which workflow is triggered
- when it is triggered
- whether it is automatic or manual
- and what responsibility it owns

## Repository Structure

```
build-workflow/
├── .github/workflows/
│   ├── helm-validate.yaml     # Reusable: 5-layer validation pipeline
│   ├── release-chart.yaml     # Reusable: publish chart to OCI registry
│   ├── docker-build.yaml      # Internal: build & push the Docker image
│   ├── docker-pr-smoke.yaml   # Internal: PR smoke build for Dockerfile changes
│   ├── pr-required-checks.yaml # Internal: always-on PR gate for branch protection
│   └── quality-guardrails.yaml # Internal: static lint checks for scripts/workflows/Dockerfile
├── docs/
│   └── workflow-trigger-matrix.md # Trigger ownership and automation matrix
├── scripts/
│   ├── lib/
│   │   └── common.sh              # Shared utilities (logging, colors, semver)
│   ├── validate-orchestrator.sh   # Runs all 5 layers sequentially
│   ├── validate-syntax.sh         # Layer 1: yamllint + helm lint
│   ├── validate-schema.sh         # Layer 2: kubeconform
│   ├── validate-metadata.sh       # Layer 3: chart-testing (ct lint)
│   ├── validate-tests.sh          # Layer 4: helm-unittest + snapshots
│   ├── validate-policy.sh         # Layer 5: Checkov + kube-linter
│   └── update-snapshots.sh        # Shared snapshot regeneration helper
├── configs/
│   ├── yamllint.yaml              # yamllint rules
│   ├── ct-default.yaml            # chart-testing defaults
│   ├── chart_schema.yaml          # Chart.yaml schema for ct
│   └── kube-linter-default.yaml   # kube-linter default config
└── docker/
    └── Dockerfile                 # All tools in one image (single source of truth)
```

---

## Validation Framework

A universal, layered Helm chart validation framework that enforces strict quality and security standards across 5 validation layers:

| Layer | Tool(s) | What it checks |
|-------|---------|----------------|
| 1. Syntax & Structure | yamllint, helm lint --strict | YAML formatting, chart structure, values.schema.json |
| 2. Schema Validation | kubeconform | Rendered manifests valid for target K8s version + CRDs |
| 3. Metadata & Version | chart-testing (ct lint) | Chart.yaml schema, version strictly greater |
| 4. Tests & Snapshots | helm-unittest, snapshot diff | Template logic, regression detection, fail-case tests |
| 5. Policy Enforcement | Checkov, kube-linter | CIS benchmarks, security best practices |

The pipeline uses **fast-fail**: if any layer fails, subsequent layers are skipped. This ensures developers fix foundational issues (syntax) before investing time in policy checks.

**Key features:**
- Strict enforcement - all warnings and errors block PRs
- Multi-scenario testing - validate minimal, full, and custom configurations
- Snapshot-based drift detection - catch unintended template changes
- CRD validation - ServiceMonitor, HTTPRoute, Istio, cert-manager, and more
- Security-first - Checkov + kube-linter with all default checks enabled
- Local + CI parity - same Docker image used locally and in GitHub Actions

---

## Quick Start

### 1. Expected chart repo directory layout

The framework expects this structure within your Helm chart repository:

```
my-chart-repo/
├── Chart.yaml
├── values.yaml
├── templates/
├── tests/
│   ├── scenarios/
│   │   ├── minimal.yaml     # Required: minimal working config
│   │   └── full.yaml        # Required: all features enabled
│   ├── snapshots/           # Auto-generated committed rendered output
│   │   ├── minimal.yaml
│   │   └── full.yaml
│   ├── schema-fail-cases/   # Optional: values that should fail validation
│   │   └── invalid-*.yaml
│   └── *_test.yaml          # Optional: helm-unittest BDD tests
├── .checkov.yaml            # Optional: Checkov skip/soft-fail config
├── .kube-linter.yaml        # Optional: kube-linter overrides
├── ct.yaml                  # Optional: chart-testing overrides
└── Makefile                 # Local dev (see below)
```

## Dependency Automation Policy

This repository uses Renovate with scoped automerge for low-risk updates only:

- `github-actions`: `digest`, `pin`, `pinDigest`, `patch`, `minor`
- `dockerfile`: `digest`, `pin`, `pinDigest`, `patch`, `minor`
- Tool pins via custom regex managers: `digest`, `pin`, `pinDigest`, `patch`, `minor`
- `major` updates are disabled from automerge and require manual review

Branch protection is expected to enforce:

- PR required before merge
- Required status checks must pass (require only: `required-checks`)
- Branch must be up to date before merge

Do not require path-filtered workflow checks directly. Use the always-on
`required-checks` gate from `.github/workflows/pr-required-checks.yaml`.

This guarantees automerge can only complete when CI is green.

### 2. Create scenario fixtures

Every chart must have at least `minimal.yaml` and `full.yaml` in `tests/scenarios/`:

```yaml
# tests/scenarios/minimal.yaml - bare minimum to render valid manifests
global:
  name: "my-app"
deployment:
  replicas: 1
  containers:
    app:
      image:
        repository: nginx
        tag: "1.27.0"
```

```yaml
# tests/scenarios/full.yaml - enables all features (used by Layer 5 policy scans)
global:
  name: "my-app"
deployment:
  replicas: 3
  containers:
    app:
      image:
        repository: nginx
        tag: "1.27.0"
        pullPolicy: Always
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
  # ... all optional features enabled
```

### 3. Add the CI workflow

In your chart repo, create `.github/workflows/validate.yaml`:

```yaml
name: Validate Chart
on:
  pull_request:
    branches: [main]

jobs:
  validate:
    uses: orhayoun-eevee/build-workflow/.github/workflows/helm-validate.yaml@<pinned-commit-sha>
    with:
      chart_path: .
      kubernetes_version: "1.30.0"
    secrets: inherit
```

### 4. Add a Makefile for local development

Create a `Makefile` in your chart repo:

```makefile
.PHONY: help deps lint validate test snapshot-update snapshot-diff security

# Configuration
CHART_PATH        ?= .
KUBERNETES_VERSION ?= 1.30.0
SCENARIOS_DIR     ?= tests/scenarios
SNAPSHOTS_DIR     ?= tests/snapshots

# Docker configuration
DOCKER_IMAGE      ?= helm-validate:local
BUILD_WORKFLOW    ?= ../build-workflow

# Resolve to absolute path for Docker mount
BW_ABS_PATH := $(shell cd $(BUILD_WORKFLOW) 2>/dev/null && pwd)

# Version check: disabled for local dev (CI sets to true)
RUN_VERSION_CHECK ?= false

# Docker run base command
DOCKER_RUN = docker run --rm \
	-v $(shell pwd):/workspace \
	-v $(BW_ABS_PATH):/opt/build-workflow \
	-w /workspace \
	-e CHART_PATH=$(CHART_PATH) \
	-e KUBERNETES_VERSION=$(KUBERNETES_VERSION) \
	-e SCENARIOS_DIR=$(SCENARIOS_DIR) \
	-e SNAPSHOTS_DIR=$(SNAPSHOTS_DIR) \
	-e CONFIGS_DIR=/opt/build-workflow/configs \
	-e RUN_VERSION_CHECK=$(RUN_VERSION_CHECK) \
	$(DOCKER_IMAGE)

SCRIPTS = /opt/build-workflow/scripts

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

docker-build: ## Build the validation Docker image locally
	docker build -t $(DOCKER_IMAGE) $(BW_ABS_PATH)/docker/

deps: ## Update Helm chart dependencies
	@$(DOCKER_RUN) -c "helm dependency update $(CHART_PATH)"

lint: ## Run Layer 1: syntax checks (yamllint + helm lint)
	@$(DOCKER_RUN) $(SCRIPTS)/validate-syntax.sh

validate: ## Run full validation pipeline (all 5 layers)
	@$(DOCKER_RUN) $(SCRIPTS)/validate-orchestrator.sh

test: deps ## Run helm-unittest
	@$(DOCKER_RUN) -c "helm unittest $(CHART_PATH) --color"

snapshot-update: deps ## Regenerate all scenario snapshots
	@$(DOCKER_RUN) /opt/build-workflow/scripts/update-snapshots.sh
	@echo "Snapshots updated. Review with: make snapshot-diff"

snapshot-diff: ## Show snapshot differences
	@git diff --stat $(SNAPSHOTS_DIR)/ || true
	@git diff $(SNAPSHOTS_DIR)/ || true

security: ## Run Layer 5: policy checks (Checkov + kube-linter)
	@$(DOCKER_RUN) $(SCRIPTS)/validate-policy.sh
```

### 5. Build the Docker image and run validation

```bash
make docker-build     # Build image once (or after tool version bumps)
make validate         # Run all 5 layers
```

---

## Reusable Workflows Reference

### helm-validate.yaml

**Purpose:** Runs the full 5-layer validation pipeline inside the Docker image.

**Trigger:** `workflow_call` only (reusable workflow).

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `chart_path` | string | Yes | - | Path to the Helm chart directory |
| `kubernetes_version` | string | Yes | - | Target Kubernetes version (e.g., `1.30.0`) |
| `scenarios_dir` | string | No | `tests/scenarios` | Path to scenario fixtures (relative to `chart_path`) |
| `snapshots_dir` | string | No | `tests/snapshots` | Path to snapshot files (relative to `chart_path`) |
| `target_branch` | string | No | `main` | Base branch for version comparison |
| `run_version_check` | boolean | No | `true` | Run version strictly-greater check |
| `checkov_extra_args` | string | No | `""` | Extra args for Checkov |
| `build_workflow_ref` | string | No | `main` | Ref (SHA/tag/branch) used for checking out `build-workflow` scripts/configs |
| `docker_image` | string | No | `ghcr.io/orhayoun-eevee/helm-validate@sha256:<digest>` | Docker image to use (immutable digest recommended) |

**How it works:**
1. Checks out the consumer repo and `build-workflow` at the caller-provided `build_workflow_ref`
2. Runs inside the `docker_image` container
3. Executes `validate-orchestrator.sh` which runs all 5 layers sequentially
4. Posts a summary comment on the PR (pass/fail with settings table)

---

### release-chart.yaml

**Purpose:** Package and publish a Helm chart to GitHub Container Registry (OCI).

**Triggers:**
- `push` to tags matching `v*` or `X.Y.Z` (direct tag-based release)
- `workflow_call` (reusable from other repos)

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `chart_path` | string | No | `.` | Path to the Helm chart directory |

**How it works:**
1. Verifies `Chart.yaml` version matches the git tag
2. Runs `helm dependency build`
3. Runs `helm package .`
4. Pushes to `oci://ghcr.io/<owner>/<chart-name>:<version>`

**Example (consumer repo):**

```yaml
name: Release Chart
on:
  push:
    tags: ['v*']

jobs:
  release:
    uses: orhayoun-eevee/build-workflow/.github/workflows/release-chart.yaml@<pinned-commit-sha>
    with:
      chart_path: .
    permissions:
      contents: read
      packages: write
```

---

### docker-build.yaml (internal)

**Purpose:** Builds and pushes the `helm-validate` Docker image to GHCR.

**Triggers:** Push to tags matching `v*`, or manual `workflow_dispatch`.

Published tags: `X.Y.Z`, `X.Y`, `X`.

---

## Environment Variables Reference

The validation scripts are configured via environment variables. These are set by the Makefile or the GitHub Actions workflow.

| Variable | Required | Default | Used By | Description |
|----------|----------|---------|---------|-------------|
| `CHART_PATH` | Yes | - | All layers | Path to the Helm chart directory |
| `KUBERNETES_VERSION` | Yes | - | L2, L4, L5 | Target Kubernetes version |
| `SCENARIOS_DIR` | No | `${CHART_PATH}/tests/scenarios` | L2, L4, L5 | Path to scenario fixtures |
| `SNAPSHOTS_DIR` | No | `${CHART_PATH}/tests/snapshots` | L4 | Path to committed snapshot files |
| `CONFIGS_DIR` | No | `${SCRIPT_DIR}/../configs` | L1, L3, L5 | Path to framework config files |
| `TARGET_BRANCH` | No | `main` | L3 | Base branch for version comparison |
| `RUN_VERSION_CHECK` | No | `true` | L3 | Enable/disable version strictly-greater check |
| `CHECKOV_EXTRA_ARGS` | No | `""` | L5 | Extra arguments passed to Checkov |

---

## Configuration Files Reference

### configs/yamllint.yaml

Used by **Layer 1** (yamllint) and **Layer 3** (ct lint uses it as `lint-conf`).

Key rules:
- Line length: 200 max
- Indentation: 2 spaces
- Truthy key checking: disabled (allows `on:` in YAML)
- Document start/end markers: disabled

### configs/ct-default.yaml

Used by **Layer 3** (chart-testing). Defines defaults for `ct lint`:

| Setting | Value | Notes |
|---------|-------|-------|
| `check-version-increment` | `true` | Enforced in CI; overridable via `RUN_VERSION_CHECK` |
| `validate-maintainers` | `false` | Not required |
| `validate-chart-schema` | `true` | Uses `chart_schema.yaml` |
| `validate-yaml` | `true` | Uses `yamllint.yaml` |

Charts can override by placing a `ct.yaml` in their root. The framework will still ensure `chart-yaml-schema` and `lint-conf` resolve to the framework configs.

### configs/chart_schema.yaml

Yamale schema for `Chart.yaml`, used by `ct lint --validate-chart-schema`. Enforces:

| Field | Rule |
|-------|------|
| `name` | Required string |
| `version` | Required string |
| `type` | Must be `application` or `library` |
| `apiVersion` | Must be `v2` |
| `description` | Required string, minimum 10 characters |
| `appVersion` | Required string |
| `maintainers` | Optional list with `name` (required), `email`/`url` (optional) |
| `dependencies` | Optional list with `name`/`version` (required), `repository`/`condition`/`alias` (optional) |

### configs/kube-linter-default.yaml

Used by **Layer 5** (kube-linter). Starts with the built-in default checks (~25 checks) and no exclusions.

Charts can override by placing a `.kube-linter.yaml` in their root.

TODO checks to progressively enable (documented in the config file):
- `no-liveness-probe`, `no-readiness-probe`
- `no-rolling-update-strategy`
- `default-service-account`
- `non-isolated-pod` (NetworkPolicy)
- `minimum-three-replicas`
- `cluster-admin-role-binding`

---

## Configuration & Exceptions

### Checkov Exceptions

**Option A:** Config file (`.checkov.yaml` at chart root or repo root):

```yaml
skip-check:
  - CKV_K8S_43  # Image uses tag not digest
soft-fail-on:
  - CKV2_K8S_6  # NetworkPolicy correlation check
```

The framework auto-detects this file in order: `${CHART_PATH}/.checkov.yaml` then `./.checkov.yaml`.

**Option B:** Annotations in Helm templates:

```yaml
metadata:
  annotations:
    checkov.io/skip1: "CKV_K8S_43=Upstream does not publish digests"
```

**Option C:** Extra args via workflow input:

```yaml
with:
  checkov_extra_args: "--skip-check CKV_K8S_43"
```

### kube-linter Exceptions

Create `.kube-linter.yaml` in your chart root:

```yaml
checks:
  doNotAutoAddDefaults: false
  exclude:
    - "no-read-only-root-fs"  # Application needs write access to /tmp
  include: []
```

If no chart-level config exists, the framework uses `configs/kube-linter-default.yaml`.

### chart-testing (ct) Overrides

Place a `ct.yaml` in your chart root. The framework will merge it with the defaults, ensuring `chart-yaml-schema` and `lint-conf` always point to the framework configs.

---

## Docker Image

The Docker image bundles all validation tools at pinned versions for consistency between local development and CI.

### Tools included

`docker/Dockerfile` is the source of truth for tool versions.

| Tool | Version | Purpose |
|------|---------|---------|
| helm | 3.20.0 | Chart rendering, linting, packaging |
| helm-unittest | 0.8.2 | BDD-style unit tests |
| kubeconform | 0.7.0 | Kubernetes schema validation |
| chart-testing (ct) | 3.14.0 | Chart metadata validation |
| yamale | 5.3.0 | YAML schema validator (ct dependency) |
| kube-linter | 0.8.1 | Kubernetes best practices linter |
| checkov | 3.2.502 | IaC security scanner |
| yamllint | 1.38.0 | YAML formatting linter |
| yq | 4.52.4 | YAML processor |

### Build locally

```bash
docker build -t helm-validate:local -f docker/Dockerfile docker/
```

### Updating tool versions

1. Update the version in `docker/Dockerfile`
2. Rebuild and test: `docker build -t helm-validate:local -f docker/Dockerfile docker/`
3. Publish flow:
   - automatic publish on `main` when docker build inputs change (consume by immutable digest)
   - automatic versioned publish on `v*` tag push
   - optional manual publish via `workflow_dispatch`

---

## Layer-by-Layer Details

### Layer 1: Syntax & Structure (`validate-syntax.sh`)

**Steps:**
1. `yamllint` on `values.yaml` and `Chart.yaml` using `configs/yamllint.yaml`
2. `helm lint --strict` on the chart
3. `values.schema.json` validation (automatic via helm lint if schema file exists)

**Fails if:** Any YAML formatting error or helm lint error.

### Layer 2: Schema Validation (`validate-schema.sh`)

**Steps:**
1. For each scenario in `SCENARIOS_DIR`:
   - Render manifests via `helm template`
   - Validate with `kubeconform --strict` against the target K8s version

**CRD support:** Uses the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) as a secondary schema source, covering:
- ServiceMonitor, PodMonitor, PrometheusRule (Prometheus Operator)
- HTTPRoute, Gateway (Gateway API)
- VirtualService, DestinationRule (Istio)
- Certificate, Issuer (cert-manager)
- And many more

**Fails if:** Any rendered manifest is invalid for the target Kubernetes version.

### Layer 3: Metadata & Version (`validate-metadata.sh`)

**Steps:**
1. `ct lint` with chart-testing config (validates `Chart.yaml` schema, YAML lint, chart structure)
2. Version strictly-greater check (compares `Chart.yaml` version against `TARGET_BRANCH`; skipped when `RUN_VERSION_CHECK=false`)

**Fails if:** Chart metadata is invalid or version is not incremented (when check is enabled).

### Layer 4: Tests & Snapshots (`validate-tests.sh`)

**Steps:**
1. `helm unittest` (if `*_test.yaml` files exist in chart `tests/`)
2. Snapshot comparison: render each scenario and diff against committed snapshots in `SNAPSHOTS_DIR`
3. Schema fail-case tests (if `tests/schema-fail-cases/` exists): verify invalid values are correctly rejected

**Fails if:** Any unit test fails, any snapshot has drifted, or any fail-case is incorrectly accepted.

### Layer 5: Policy Enforcement (`validate-policy.sh`)

**Steps:**
1. Render the `full.yaml` scenario (all features enabled)
2. `checkov` scan with Kubernetes framework (uses `.checkov.yaml` config if present)
3. `kube-linter` scan (uses `.kube-linter.yaml` config if present, otherwise framework default)

**Fails if:** Any security policy violation is detected.

**Note:** Layer 5 requires a `full.yaml` scenario because policy tools need manifests with all features enabled (resources, probes, security contexts, etc.) to provide meaningful results.

---

## Future Roadmap

### Layer 6: Custom Organizational Policies (Planned)

**Technology:** OPA/Conftest (Rego) or Kyverno CLI (YAML)

Planned policies:
- Required standard labels enforcement
- Container images from approved registries only
- PodDisruptionBudget required when replicas > 1
- ServiceAccount automountToken validation
- NetworkPolicy required for every Deployment
- Full Pod Security Standards (PSS) restricted profile

Status: Deferred until Layers 1-5 are stable across multiple chart repos.
