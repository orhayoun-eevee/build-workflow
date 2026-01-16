# Validate Gold File Workflow

## Overview

The `validate-gold.yml` workflow is a reusable GitHub Actions workflow that validates Helm chart templates against a reference "gold file". It ensures that any changes to Helm charts or their values are intentional and properly documented.

## Purpose

This workflow serves as a quality gate in CI/CD pipelines to:

- **Detect unintended changes**: Catch accidental modifications to Kubernetes manifests generated from Helm charts
- **Enforce consistency**: Ensure that the generated manifests match the expected baseline
- **Provide visual diffs**: Show exactly what changed when manifests differ from the gold file
- **Validate chart syntax**: Run `helm lint` to catch chart errors before template generation

## What It Does

The workflow performs two validation steps in sequence:

1. **Helm Lint**: Validates the Helm chart syntax and structure using `helm lint`
2. **Gold File Comparison**: Generates Helm templates and compares them against the committed `gold_file.yaml`

If either step fails, the workflow fails and the PR pipeline is blocked.

## Dependencies

### Required Files

- `generate_gold.sh`: Script that generates Helm template output and compares it against the gold file
  - Must be executable (workflow sets permissions automatically)
  - Must support a `test` mode that exits with code 0 on match, 1 on mismatch
  - Typically located in the `gold/` directory

- `gold_file.yaml`: Reference output from `helm template` representing the expected Kubernetes manifests
  - Must be committed to the repository
  - Should be updated when intentional changes are made to charts or values

### External Dependencies

- **Helm**: Installed automatically by the workflow using `azure/setup-helm@v4`
- **GitHub Actions**: Requires `actions/checkout@v4` for code checkout

## Workflow Inputs

| Input | Description | Required | Default | Type |
|-------|-------------|----------|---------|------|
| `working_directory` | Directory containing the `generate_gold.sh` script | No | `gold` | string |
| `script_name` | Name of the generation script to execute | No | `generate_gold.sh` | string |
| `chart_path` | Path to the Helm chart to lint (relative to repo root) | No | `.` | string |

## Usage

### Same Repository

Call the workflow from another workflow in the same repository:

```yaml
name: CI

on:
  pull_request:
    branches:
      - '*'

jobs:
  validate-gold:
    uses: ./.github/workflows/validate-gold.yml
    with:
      working_directory: gold
      script_name: generate_gold.sh
      chart_path: ./charts/my-chart
```

### Cross-Repository

Call the workflow from a different repository:

```yaml
name: CI

on:
  pull_request:
    branches:
      - '*'

jobs:
  validate-gold:
    uses: owner/build-workflow/.github/workflows/validate-gold.yml@main
    with:
      working_directory: gold
      script_name: generate_gold.sh
      chart_path: .
    secrets: inherit
```

**Note**: For cross-repo workflows, ensure:
- The workflow file exists in the default branch (main/master)
- The calling repository has appropriate permissions
- `secrets: inherit` is specified if secrets are needed

### Using Default Values

If your setup matches the defaults, you can call it without any inputs:

```yaml
jobs:
  validate-gold:
    uses: ./.github/workflows/validate-gold.yml
```

This assumes:
- Script is at `gold/generate_gold.sh`
- Chart is at the repository root

## Workflow Steps

1. **Checkout code**: Checks out the repository code
2. **Set up Helm**: Installs the latest Helm version
3. **Lint Helm chart**: Runs `helm lint` on the specified chart path
4. **Validate gold file**: 
   - Changes to the working directory
   - Makes the script executable
   - Runs `./generate_gold.sh test`
   - Fails if the script exits with a non-zero code

## Failure Behavior

The workflow fails if:

- **Helm lint errors**: The chart has syntax errors, missing required fields, or other linting issues
- **Gold file mismatch**: The generated Helm templates don't match `gold_file.yaml`
- **Script execution errors**: The `generate_gold.sh` script fails to execute

When the workflow fails, the PR check will show as failed, blocking merge until the issues are resolved.

## Updating the Gold File

When you make intentional changes to Helm charts or values:

1. Make your changes to the chart or `values.yaml`
2. Run `./generate_gold.sh update` locally to update `gold_file.yaml`
3. Commit both the chart changes and the updated `gold_file.yaml`
4. The workflow will pass once the gold file matches the new output

## Example Workflow Output

### Success Case

```
✓ Lint Helm chart
✓ Validate gold file
```

### Failure Case (Lint Error)

```
✗ Lint Helm chart
Error: Chart.yaml file is missing
```

### Failure Case (Gold File Mismatch)

```
✓ Lint Helm chart
✗ Validate gold file
--- gold_file.yaml
+++ generated_output.yaml
@@ -10,7 +10,7 @@
     replicas: 3
-    image: nginx:1.20
+    image: nginx:1.21
```

## Best Practices

1. **Keep gold file updated**: Always update `gold_file.yaml` when making intentional changes
2. **Review diffs carefully**: When the workflow fails, review the diff to ensure changes are expected
3. **Use descriptive PRs**: Document why the gold file changed in your PR description
4. **Test locally first**: Run `./generate_gold.sh test` locally before pushing to catch issues early

## Troubleshooting

### Workflow fails with "permission denied"

The workflow automatically sets execute permissions on the script. If this fails, ensure the script file exists at the specified path.

### Helm lint passes but gold file validation fails

This indicates that the generated templates differ from the gold file. Review the diff and either:
- Fix the chart/values if the change was unintentional
- Update the gold file if the change was intentional

### Cross-repo workflow not triggering

Ensure:
- The workflow file is in the default branch
- You're using the correct repository path format: `owner/repo/.github/workflows/validate-gold.yml@branch`
- The calling repository has access to this repository

## Related Documentation

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Helm Documentation](https://helm.sh/docs/)
- See `gold/` directory for information about the gold file system
