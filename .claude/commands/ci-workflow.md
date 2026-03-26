# GitHub CI/CD Workflow Management

Manage GitHub Actions workflows: analyze runs, fix failures, update dependencies, verify builds, and maintain CI health.

## When to Activate

- Analyzing a GitHub Actions run (URL or run ID)
- Fixing CI build failures
- Updating dependencies and verifying CI passes
- Adding or modifying workflow files
- Reviewing CI output for warnings or errors
- Managing Docker image builds
- Troubleshooting Renovate/Dependabot issues

## Workflow: Analyze a CI Run

When given a GitHub Actions URL or run ID:

1. **Fetch run overview** with `gh run view <run-id>`
2. **Get failed logs** with `gh run view <run-id> --log-failed` (or `--log` for full)
3. **Search for issues**: grep logs for `warn`, `error`, `(!)`, `ERR_`, `FAIL`
4. **Classify findings**:
   - From our code vs from upstream dependencies/actions
   - Blocking errors vs non-blocking warnings
   - Actionable vs informational
5. **Report** with a clear status table and actionable next steps

```bash
# Quick analysis pattern
gh run view <run-id> --repo owner/repo
gh run view --job=<job-id> --repo owner/repo --log 2>/dev/null | grep -iE '(warn|error|!|\(!\))' | grep -v '::debug'
```

## Workflow: Fix CI Failure

1. **Diagnose**: Analyze the failing job logs (see above)
2. **Reproduce locally**: Run the equivalent Makefile target (`make check`, `make build`, etc.)
3. **Fix**: Apply minimal changes to resolve the issue
4. **Verify locally**: Run `make check` to confirm
5. **Commit and push** with descriptive message
6. **Watch CI**: `gh run watch <run-id> --repo owner/repo`
7. **Verify clean**: Search new run logs for warnings

## Workflow: Update Dependencies

1. **Check outdated**: `pnpm outdated`
2. **Update within ranges**: `pnpm update`
3. **For major bumps**: Install explicitly, e.g. `pnpm add -D typescript@^6.0.2`
4. **Fix breaking changes**: Update configs as needed (tsconfig, vite, etc.)
5. **Verify**: `make check`
6. **Handle vulnerabilities**: Add `pnpm.overrides` in package.json for transitive deps
7. **Update Renovate config** if version pins need to change

```bash
# Override a vulnerable transitive dependency
# In package.json → pnpm.overrides:
"yaml@>=2.0.0 <2.8.3": ">=2.8.3"
```

## Workflow: Docker Build Issues

Common fixes for Docker build failures:

### pnpm in Docker (no TTY)
Use `--frozen-lockfile` instead of bare `pnpm install`:
```dockerfile
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .
```

### Large Docker context
Add `.dockerignore` to exclude `node_modules`, `dist`, `.git`.

### Layer caching
Copy lockfiles before source code to cache the install layer:
```dockerfile
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .  # Only this layer invalidates on code changes
```

## Workflow: Commit, Push, Watch

After making changes:

```bash
# 1. Verify locally
make check

# 2. Commit with conventional commit message
git add <files>
git commit -m "type: description"

# 3. Push and watch
git push
gh run list --repo owner/repo --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch <run-id> --repo owner/repo

# 4. Analyze for warnings
gh run view --job=<job-id> --log 2>/dev/null | grep -iE '(warn|error|!|\(!\))'
```

## Conventions

| Convention | Pattern |
|-----------|---------|
| Action pinning | Commit SHAs, not version tags |
| Commit messages | Conventional commits: `feat:`, `fix:`, `chore:`, `perf:`, `ci:` |
| CI install | `pnpm install --frozen-lockfile` (never bare `pnpm install`) |
| Formatting | Prettier only (no eslint) |
| Type checking | `tsc` as build gate |
| Docker tags | Semver from git tags (`v1.2.3`, `v1.2`, `v1`, `latest`) |
| Multi-arch | `linux/amd64` + `linux/arm64` |
| Cleanup | Weekly: old runs (7d/5 min), untagged images (5 min) |
| Renovate | Auto-merge minor/patch, manual merge major, pin TS/breaking libs as needed |

## Vite Build Warnings

If chunk size warning appears (>500KB):
1. **Lazy-load routes** with `React.lazy()` + `<Suspense>`
2. **Split vendor chunks** in `vite.config.ts` using `manualChunks` function (not object -- Rolldown requires a function)
3. Group by library: react, mui/emotion, ethers, etc.

```typescript
// vite.config.ts -- Vite 8 / Rolldown
rolldownOptions: {
  output: {
    manualChunks(id) {
      if (id.includes('node_modules/react')) return 'vendor-react'
      if (id.includes('node_modules/@mui')) return 'vendor-mui'
      // ... etc
    },
  },
},
```

## Checklist: Before Push

- [ ] `make check` passes (lint + build)
- [ ] No hardcoded secrets in changes
- [ ] Docker builds work (`make image-build`, `make image-build-prod`)
- [ ] Commit message follows conventional commits
- [ ] Renovate config updated if version constraints changed
- [ ] CLAUDE.md updated if conventions changed
