# 🚀 Reusable GitHub Workflows

This repository contains centralized, reusable GitHub Actions workflows for various project types and technologies. These workflows promote consistency, maintainability, and efficiency across all our projects.

## 🔒 Security and supply chain

| Workflow / file | What it does | Docs |
| --- | --- | --- |
| `security-scan.yml` | Secrets, dependencies, IaC, image and SAST scans; dated risk acceptances; lifecycle checks; nightly Jira triage | [adopting](docs/security/adopting.md#1-security-scan), [CVE policy](docs/security/cve-policy.md) |
| `release-provenance.yml` | SBOM, provenance and signed attestations for each release; final-image gate before the system-lock bump | [adopting](docs/security/adopting.md#2-release-provenance), [SBOM and provenance](docs/security/sbom-provenance.md) |
| `default.json` | Shared Renovate preset: Actions pinned by SHA, base images by digest | [renovate](docs/renovate.md), [lifecycle](docs/security/lifecycle.md), [Node and frontend](docs/security/node-frontend.md) |
| `SECURITY.md` | Org-wide vulnerability reporting policy | |

## 📁 Workflow inventory

Reusable workflows are called at `@main` as `lovablegarden/.github/.github/workflows/<file>@main`. Every file here has a caller (checked 17 Nov 2026, LG-1470).

| Workflow | Called by | Purpose |
| --- | --- | --- |
| `java-21-gradle-ci.yml` | service `ci.yml` | Build, test, main-branch image (`latest`, `main-<sha>` only) |
| `java-25-gradle-ci.yml` | `ci-java25.yml` (plants, gardenbook, security-common) | Same on JDK 25. **Generated** from java-21 by `tests/java-template-parity/check.sh --write` |
| `gated-release.yml` | `release-please.yml` (services, security-common) | release-please with the pre-production gate ([docs](docs/release-please-pre-production.md)) |
| `release-please.yml` | lovablegarden-system | Plain release-please |
| `release-docker-publish.yml` | service `release-published.yml` | Release image from the **release tag**, immutable version tags, token only as a BuildKit secret (LG-1468/1469/1471). `java-version` input (default `'21'`; `'25'` for Java 25 services, LG-1222); `release-provenance.yml` has the same input |
| `release-library-publish.yml` | security-common `release-published.yml` | Maven publish from the release tag |
| `release-provenance.yml` | every release path (services, jwt-validator, security-common, openapi-spec, frontend) | SBOM, provenance, attestations, final-image gate |
| `consumer-bump-system-lock.yml` | service `release-published.yml`, jwt-validator | Bump `versions/services.lock.yml` in lovablegarden-system |
| `consumer-bump-bom-version.yml` | security-common `release-published.yml` | Bump `lovablegardenBomVersion` in services |
| `prune-ghcr-package.yml`, `prune-maven-package.yml` | `package-retention.yml`, release workflows, `package-retention-scheduled.yml` | Package retention (keeps attested images, LG-1471) |
| `security-scan.yml` | `security-scan.yml` in every active repo and the frontend | See the security table above |
| `frontend-release.yml` | frontend `release.yml` | Frontend GitHub Release (archives, no image). Node from the caller's `.nvmrc` unless `node-version` is passed (LG-1223). The job runs `<lint-command> --max-warnings <max-warnings>` (default 600), so `lint-command` must take ESLint flags directly: `npx eslint …`, or an `npm run` script ending in ` --`. |
| `renovate.yml`, `*-scheduled.yml`, `test-*.yml` | this repo | Renovate runner, scheduled jobs, tests of the reusables |

### Release path (services)

release-please PR (conventional commits; `chore:` does not release, use `fix:` or a `Release-As:` footer) → merge → GitHub Release `<repo>-v<x.y.z>` → `release-published.yml`: `release-docker-publish` → `release-provenance` (gate) → `consumer-bump-system-lock`. A manual `workflow_dispatch` of "Publish on Release" builds the given release tag and refuses to overwrite an existing image tag. The legacy manual `release.yml` / `java-2x-gradle-release.yml` path was retired in LG-1470.

## 🔐 Required Secrets

`GH_PACKAGES_TOKEN` (GitHub Packages), `LOVABLEGARDEN_BOT_APP_ID` / `LOVABLEGARDEN_BOT_PRIVATE_KEY` (bot app, see [BOT_SECRETS.md](BOT_SECRETS.md)), and for scan triage `JIRA_USER_EMAIL` / `JIRA_API_TOKEN` with the org variable `JIRA_BASE_URL`.

## 🤝 Contributing

1. **Fork** this repository
2. **Create** a feature branch (`git checkout -b feature/amazing-workflow`)
3. **Commit** your changes (`git commit -m 'Add amazing workflow'`)
4. **Push** to the branch (`git push origin feature/amazing-workflow`)
5. **Open** a Pull Request

## 📚 Best Practices

### ✅ Do's
- Use semantic versioning for releases
- Always test workflows in a fork first
- Use descriptive commit messages
- Keep workflows modular and reusable
- Document all inputs and outputs

### ❌ Don'ts
- Don't hardcode values that should be configurable
- Don't skip security considerations
- Don't create overly complex workflows
- Don't forget to handle error cases

## 🔄 Versioning Strategy

- **`@main`** - Latest stable version (recommended for most use cases)
- **`@v1.0.0`** - Specific version tags (coming soon)
- **`@develop`** - Development version (use at your own risk)

## 📞 Support

For questions or support:
1. **Create an issue** in this repository
2. **Check existing issues** for similar problems
3. **Review the documentation** thoroughly before asking

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**LovableGarden platform**
