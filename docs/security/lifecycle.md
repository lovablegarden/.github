# Container, base-image and GitHub Actions lifecycle (LG-1224)

Application dependencies are covered by Renovate ([renovate.md](../renovate.md)) and the security scan. This page covers the rest of the supply chain: base images, the runtime in them, and the Actions that build them.

## Policy

| Component | Pinning | Updates | Who merges |
| --- | --- | --- | --- |
| Third-party GitHub Actions | Full commit SHA, version in a comment (`uses: actions/checkout@<sha> # v4.4.0`) | Renovate, one grouped PR, Monday | Auto-merge for minor/patch/digest after required checks; majors from the Dependency Dashboard |
| Org reusable workflows (`lovablegarden/.github/...`) | `@main`, by design: fixes reach every repo at once | Merged here, tested by the `test-*` workflows | — |
| Base images in Dockerfiles (`eclipse-temurin:21-jre-alpine`, `node:…`) | Tag **and** digest (`image:tag@sha256:…`); Renovate adds the digest | Digest refresh (same tag, patched OS packages): grouped "Base image digests" PR, auto-merge after required checks. Minor tag: review. Major (Java 25, Node 24): planned work, not Renovate | Renovate / reviewer |
| Images in compose files (`postgres`, `nginx`, …) | Tag and digest | Same group, never auto-merged: a deploy changes prod | Reviewer |
| Runtime and framework (Java, Node, Spring Boot, Alpine) | — | Planned before end-of-life (below) | Jira work |

The scan's lifecycle check reports anything that breaks the pinning rules, in each repo's scan summary. It's report-only: it doesn't fail builds.

## Approved base images

| Use | Image | Owner |
| --- | --- | --- |
| Java services (runtime) | `eclipse-temurin:21-jre-alpine` | Platform (Jessica) |
| Java services (build stage, if any) | `eclipse-temurin:21-jdk-alpine` | Platform |
| Frontend | none: Cloudflare Pages | Frontend |
| Databases and proxies | as in `lovablegarden-system` compose files | Platform |

A new base image needs an owner and an entry here. Java 25 (`eclipse-temurin:25-*`) comes with LG-1222, after Release 1.

## Patch cadence

- **Weekly:** Renovate's Monday run refreshes base-image digests and Actions. With required checks green, they auto-merge, and the next release ships the patched OS packages.
- **Nightly:** the security scan rescans each repo's `latest` image, so a new CVE in a base image shows up without a code change.
- **Every release:** `release-provenance.yml` scans the final image before it can reach the system lock ([SBOM and provenance](sbom-provenance.md)).

## Emergency update flow

For a known-exploited or CRITICAL finding in a base image or Action ([CVE policy](cve-policy.md)):

1. Renovate's vulnerability alerts skip the schedule and the release age. If a fixed digest exists, the PR appears within the hour. Otherwise run **Actions → Renovate → Run workflow** here.
2. If there is no Renovate PR (no fixed tag yet, or a compromised Action), patch by hand: pin to the fixed digest/SHA in one PR per affected repo. For a compromised Action, pin to the last known-good SHA and remove the action if none is safe.
3. Merge on green, release, and let the release chain bump the system lock. Deploy at the next window (12:00 or 17:00 CET), or ask Jessica for an out-of-window deploy if the policy target is shorter.
4. Close the Jira finding with the release and the scan run that no longer shows it.

## End-of-life monitoring

The scan checks end-of-life dates with [endoflife.date](https://endoflife.date) for:

| Component | Read from |
| --- | --- |
| Spring Boot | the resolved runtime classpath (`gradle.lockfile` written during the scan) |
| Java (Temurin) | Dockerfile `FROM eclipse-temurin:<major>…` |
| Node.js | Dockerfile `FROM node:<major>…` |
| Image OS (Alpine, Debian, Ubuntu) | Trivy's metadata of the scanned image |

A component that is end-of-life, or within 120 days of it, is shown in the scan summary. The nightly triage files one Jira Task per product and version across all repos (label `lifecycle-eol-<product>-<cycle>`), due 30 days before the end-of-life date, so the upgrade is planned before support ends.

A deliberate deferral is a risk acceptance in the repo's `.trivyignore` ([how](cve-policy.md#risk-acceptance)):

```text
# <product> <cycle> support ends <date>. Upgrade planned after Release 1: LG-1234.
EOL-<product>-<cycle> exp:2027-03-31
```

If the upgrade already has a Jira issue, give it the label `lifecycle-eol-<product>-<cycle>`: the triage then comments there instead of filing a new Task.

## Checking an image against the lock

See [reconciling deployed images](sbom-provenance.md#reconciling-deployed-images-with-the-lock-and-the-releases).
