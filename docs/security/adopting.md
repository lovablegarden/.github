# Adopting the security workflows

Two reusable workflows, each added to a repo with one small caller. Both stay on `@main` (see [lifecycle](lifecycle.md#policy)).

| Workflow | Issue | Runs | What it does |
| --- | --- | --- | --- |
| [`security-scan.yml`](../../.github/workflows/security-scan.yml) | LG-1218, LG-1216, LG-1224 | PRs, main, nightly, manual | Secrets (gitleaks), dependencies + IaC (Trivy), the published image (Trivy), SAST (Semgrep), dated risk acceptances, lifecycle (pinning, end-of-life), nightly Jira triage |
| [`release-provenance.yml`](../../.github/workflows/release-provenance.yml) | LG-1220, LG-1224 | Each release | SBOM of the final image, provenance record, signed attestations, final-image scan that gates the system-lock bump |

Policies: [CVE triage and risk acceptance](cve-policy.md), [SBOM and provenance](sbom-provenance.md), [lifecycle](lifecycle.md).

## 1. Security scan

`.github/workflows/security-scan.yml` in the repo:

```yaml
name: Security Scan

# Secrets, dependencies, IaC, container image, SAST, lifecycle and Jira triage (LG-1218, LG-1216, LG-1224).
# Reusable workflow and options: lovablegarden/.github/.github/workflows/security-scan.yml
on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]
  schedule:
    - cron: '23 4 * * *'
  workflow_dispatch:

permissions:
  contents: read
  packages: read

jobs:
  security:
    uses: lovablegarden/.github/.github/workflows/security-scan.yml@main
    with:
      image: ghcr.io/lovablegarden/<repo>:latest     # omit for repos without an image
    secrets:
      GH_PACKAGES_TOKEN: ${{ secrets.GH_PACKAGES_TOKEN }}
      JIRA_USER_EMAIL: ${{ secrets.JIRA_USER_EMAIL }}
      JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}
```

Repos that already have the LG-1218 caller only add the two `JIRA_*` lines. Everything else (risk acceptances on the image, lifecycle, triage) arrives through `@main`.

Use `pull_request`, never `pull_request_target`: PRs from forks then get no secrets.

### Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `image` | `''` | Image scanned on push, schedule and dispatch. Empty skips the image job. |
| `image-platform` | `linux/arm64` | The org builds arm64 only. |
| `image-on-pr` | `false` | Also scan the image on PRs (it isn't built from the PR). |
| `scan-path` | `.` | Directory to scan; `.trivyignore` and `.gitleaksignore` are read from here. |
| `java-version` | `21` | JDK used to resolve the Gradle runtime classpath. |
| `severity-threshold` | `CRITICAL` | Lowest severity of a fixable finding that gates. |
| `enforce` | `true` | `false` = report only. |
| `enforce-on` | `pull_request` | PRs fail on findings they introduce; main, nightly and image runs warn. `always` = every event fails. Switch once a repo's baseline is clear. |
| `sast-enforce` | `false` | Fail on Semgrep ERROR findings. |
| `jira-triage` | `scheduled` | File Jira issues on schedule/dispatch runs. `always` or `off`. |
| `fail-on-kev` | `true` | A known-exploited finding fails the triage job, so the nightly run notifies. |
| `artifact-prefix` | `security` | Only when one run calls the workflow twice. |
| `tooling-ref` | `main` | Ref of this repo's `scripts/security/`. Only tests change it. |

Outputs: `secrets`, `dependencies`, `dependencies-new`, `image`, `accepted-risks`, `lifecycle`, `triage`.

### Gates

| Job | Fails when |
| --- | --- |
| Secrets | any finding, every event (values redacted) |
| Dependencies and IaC | a PR introduces a fixable finding at or above the threshold (compared with the base commit); with `enforce-on: always`, any such finding |
| Image | with `enforce-on: always`, any fixable finding at or above the threshold |
| SAST | only with `sast-enforce` |
| Lifecycle, risk acceptances | never: report only, with warnings |
| Triage | a KEV finding (with `fail-on-kev`), or a Jira call failed |

**Secrets** and **Dependencies and IaC** are required checks on `main` through the org ruleset. The org ruleset is **active** since 22 Nov 2026 (LG-1225), so a PR into `main` can't merge until both are green. The rulesets, their bypass actors and how bot merges work with them are in [operations.md](operations.md#required-checks-on-main-rulesets).

### Accepting a finding

`.trivyignore` at the root of `scan-path`, one dated entry per ID under a comment with the Jira key ([policy](cve-policy.md#risk-acceptance)):

```text
# Risk acceptance (LG-1216 policy), LG-1234. Accepted 2026-11-14 by <name> (<role>), review by 2027-03-31.
# Rationale: <why>. Remediation: <Jira key>.
CVE-2099-0001 exp:2027-03-31
```

Secrets false positives go in `.gitleaksignore` (fingerprint) or a narrow `.gitleaks.toml` allowlist, with a comment saying what it doesn't cover.

## 2. Release provenance

In the repo's release workflow (for services: `.github/workflows/release-published.yml`), add the `provenance` job after `publish-docker`, make `bump-system-lock` wait for it, and add the exception input to `workflow_dispatch`:

```yaml
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      version:
        description: Release tag (e.g. v1.0.0)
        required: true
        type: string
      provenance-exception:
        description: Jira key of an approved exception (only if the provenance gate failed)
        required: false
        type: string
        default: ''

permissions:
  contents: read
  packages: write

jobs:
  publish-docker:
    # unchanged

  provenance:
    needs: [publish-docker]
    permissions:
      contents: write        # attach SBOM + provenance to the GitHub Release
      packages: write        # push attestations next to the image
      id-token: write        # sign attestations
      attestations: write
    uses: lovablegarden/.github/.github/workflows/release-provenance.yml@main
    with:
      release-tag: ${{ needs.publish-docker.outputs.tag }}   # git tag the image was built from (LG-1469)
      image: ${{ needs.publish-docker.outputs.image }}
      digest: ${{ needs.publish-docker.outputs.digest }}
      exception: ${{ github.event.inputs.provenance-exception }}
    secrets:
      GH_PACKAGES_TOKEN: ${{ secrets.GH_PACKAGES_TOKEN }}

  bump-system-lock:
    needs: [publish-docker, provenance]
    # rest unchanged
```

The job permissions are required: a reusable workflow can't get more than its caller grants, and GitHub rejects the run if they are missing.

For a repo without an image (frontend on Cloudflare, libraries), leave out `image` and `digest`: the SBOM then describes the source tree at the tag (the resolved Gradle runtime graph, or npm lock files; [details](sbom-provenance.md#source-sboms-no-image-libraries-specs-frontend)), and the provenance file is attested instead of an image. The `provenance` job then only needs `needs:` on whatever creates the GitHub Release.

### Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `release-tag` | required | Tag of the GitHub Release. |
| `image` | `''` | Image repository without tag. Empty = source SBOM. |
| `digest` | `''` | Released digest. Empty = resolve `<image>:<version>` now. |
| `image-platform` | `linux/arm64` | |
| `severity-threshold` | `CRITICAL` | Fixable findings at or above it fail the release. |
| `gate` | `true` | `false` = report the final-image scan only. |
| `exception` | `''` | Jira key of an approved exception: failures become warnings and the key is recorded. |
| `java-version` | `21` | Source mode, Gradle: JDK used to resolve the runtime dependency graph. |
| `include-dev-deps` | `false` | Source mode, npm: also list devDependencies. Automatic when there are no runtime dependencies. |
| `attest` | `true` | Sign GitHub artifact attestations. |
| `dry-run` | `false` | Test mode: no Release upload, and the provenance file is attested instead of the image. |

### Testing without a release

From a throwaway branch of the repo, a `workflow_dispatch` caller with `dry-run: true` and an existing `release-tag` and `image` produces the SBOM, the provenance file and a file attestation as a run artifact, and touches neither the Release nor the image.

## Rollout status

Checked 18 Nov 2026 (LG-1225). ✅ = in place on `main`.

| Repo | Scan | Jira secrets passed | `.trivyignore` dated | Provenance | Legacy manual release removed (LG-1470) | Renovate (LG-1217) |
| --- | --- | --- | --- | --- | --- | --- |
| audit, community, commercial, pantry, media, wiki, users, knowledgehub, supplies, tasks, plants | ✅ | ✅ | ✅ | ✅ image | ✅ | ✅ (18 Nov) |
| gardenbook | ✅ | ✅ | ✅ | ✅ image | ✅ | ✅ (19 Nov) |
| security-common | ✅ | ✅ | n/a | ✅ source SBOM | ✅ | ✅ pilot |
| openapi-spec | ✅ | ✅ | n/a | ✅ source SBOM (its manual `release.yml` is the real release) | n/a | not yet |
| lovablegarden-system (supabase-jwt-validator image) | ✅ | ✅ (lovablegarden-system#380) | n/a | ✅ image | n/a | ✅ pilot |
| frontend (lovablegarden/lovablegarden, moved from jessicabackvall in LG-1495) | ✅ | passed before the move, when org secrets didn't reach the personal-account repo; rerun the triage dry run now that it's in the org | n/a | ✅ source SBOM in `release.yml`, not yet exercised | n/a | `renovate.json` present; in the Renovate repo list since LG-1495 (bot app needs access to the repo) |
| lovablegarden-gradle-plugin | archived 13 Nov 2026, excluded | | | | | |

Jira triage: the service-account token was rejected on 18 Nov and replaced the same evening. The LG-1216 controlled test then created exactly one issue (LG-1493), and a rerun left it unchanged. See [operations.md](operations.md).

Rulesets on `main`: all four are **active** (LG-1225). The frontend and `.github` repo rulesets since 19 Nov 2026; the org ruleset 27457270 (services, security-common, system) and the openapi-spec repo ruleset since 22 Nov 2026, on Jessica's decision. See [operations.md](operations.md#required-checks-on-main-rulesets).

Operations, owners, rollback: [operations.md](operations.md).
