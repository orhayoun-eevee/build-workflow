# TODO

## Security Checks

### CKV_K8S_40 - Container UID Check

**Status:** Currently skipped in CI/CD pipeline

**Check:** CKV_K8S_40 - "Containers should run as a high UID to avoid host conflict"

**Affected Resource:**
- Deployment: `media-center.radarr`
- File: `/radarr/charts/app-chart/templates/deployment.yaml:3-233`

**Current Configuration:**
The check is skipped in both Checkov validation steps in `.github/workflows/on-pr-flow.yaml`:
- Policy checks on golden file with Checkov (line 156)
- Policy checks with Checkov (line 167)

**Action Required:**
- [ ] Investigate the radarr deployment configuration
- [ ] Determine appropriate high UID (typically >= 10000) for the container
- [ ] Update the deployment to run containers with a high UID
- [ ] Remove `skip_check: CKV_K8S_40` from both Checkov steps in the workflow
- [ ] Verify the fix passes the security check

**Notes:**
Running containers with a high UID helps prevent conflicts with host system users and reduces the risk of privilege escalation attacks. This is a security best practice that should be implemented once the appropriate UID is determined for the radarr application.
