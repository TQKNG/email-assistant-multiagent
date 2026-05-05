# CodeQL Troubleshooting Checklist

## Issue: "Resource not accessible by integration"

### Fixed in Workflow:
- Added `actions: read` permission to security-scan job

### Repository Settings to Check:

1. **Enable Code Scanning**
   - Go to: Settings → Code security and analysis
   - Enable: "Code scanning"
   - Enable: "CodeQL analysis" (if available)

2. **Enable GitHub Advanced Security** (for private repos)
   - Go to: Settings → Code security and analysis
   - Enable: "GitHub Advanced Security"
   - Note: This requires a license for private repos

3. **Workflow Permissions**
   - Go to: Settings → Actions → General
   - Scroll to: "Workflow permissions"
   - Select: "Read and write permissions"
   - OR: "Read repository contents and packages permissions" + check "Allow GitHub Actions to create and approve pull requests"

4. **Enable Dependabot Alerts**
   - Go to: Settings → Code security and analysis
   - Enable: "Dependabot alerts"
   - Enable: "Dependabot security updates"

### Alternative: Make CodeQL Non-Blocking

If you want CI to pass while fixing permissions:

1. Add `continue-on-error: true` to the security-scan job
2. Or comment out the security-scan job temporarily

### Commit the workflow fix:
git add .github/workflows/ci.yml
git commit -m "fix: add actions:read permission for CodeQL"
git push
