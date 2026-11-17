# Operating the CI/CD security baseline (LG-1225)

How the baseline is run day to day: who owns what, what runs when, how to switch a control off safely, and where the evidence is. Policies live in the linked pages; this page is the runbook.

## Owners and contacts

| Area | Owner | Contact / channel |
| --- | --- | --- |
| Baseline overall, risk acceptances, exceptions, deploys | Jessica Backvall (product owner) | Jira project LG |
| Reusable workflows in this repo | Platform (LG Jira component: Platform/Security, CI/CD) | PRs here; Jira LG |
| Findings in a service | The service's owner in Jira (default: Jessica) | The Jira finding (label `security-finding`) |
| External vulnerability reports | Jessica Backvall | [SECURITY.md](../../SECURITY.md) (GitHub private vulnerability reporting), never public issues |

Triage creates Jira issues through an Atlassian service account (org secrets `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`, variable `JIRA_BASE_URL`).

## What runs when

| When | What | Where |
| --- | --- | --- |
| Every PR and push to main | Secrets (gitleaks), dependencies and IaC (Trivy), SAST (Semgrep), lifecycle check | `security-scan.yml` caller in each repo ([adopting](adopting.md#1-security-scan)) |
| Nightly (~04:23 UTC) | Same scans plus the `latest` image; **triage** files or updates Jira issues (KEV, fixable CRITICAL, end-of-life) | Same caller, `schedule` |
| Every release | Final-image scan gate, SBOM, provenance, attestations, **before** the system-lock bump | `release-provenance.yml` ([SBOM and provenance](sbom-provenance.md)) |
| Monday before 07:00 (Stockholm) | Renovate: Actions, base-image digests, grouped non-major updates | `renovate.yml` here ([renovate](../renovate.md)) |
| First of the month | Renovate lock-file maintenance | Same |
| Weekly (Jessica's saved filter) | Overdue findings: `project = LG AND labels = security-finding AND statusCategory != Done AND duedate < now()` | Jira ([CVE policy](cve-policy.md#reports-from-jira)) |
| 30 days before an acceptance expires | Scan warns on each dated `.trivyignore` entry | Scan summary ([CVE policy](cve-policy.md#risk-acceptance)) |
| Quarterly (with the acceptance reviews) | Review this page, the rollout table and the approved base images | [lifecycle](lifecycle.md#approved-base-images) |

## Exceptions

- **Accepted risk** (a finding without a fix): a dated `.trivyignore` entry with rationale, approver and `exp:` date ([CVE policy](cve-policy.md#risk-acceptance)). Only Jessica approves.
- **One-off release exception** (provenance gate failed, release must ship): dispatch "Publish on Release" with `provenance-exception: LG-…` naming an approved Jira issue. The exception is written into `provenance.json`.
- Nothing else bypasses the gate. Re-running a failed release job never overwrites an image: version tags are immutable (LG-1471), so ship a new version instead.

## Rollback and disable

Each control can be switched off on its own, without touching the others. Every one of these is a PR or a settings change, so it leaves a trace; record the reason in Jira.

| Control | Disable / roll back | Effect |
| --- | --- | --- |
| A scan blocks every PR (tool outage, false positive) | Accept a real finding with a dated entry. For a tool problem, set `enforce: false` (report only) in that repo's caller; revert afterwards | That repo's scans report but don't fail until reverted |
| Jira triage misbehaves (floods, wrong project) | One repo: `jira-triage: off` in its caller. Everywhere at once: delete the `JIRA_API_TOKEN` org secret (Jessica), and triage falls back to a dry run in the job summary | No Jira writes; findings still in the run summary |
| Renovate | Set the variable `RENOVATE_ENABLED` to `false` here (stops the schedule); close its PRs. Per repo: remove the repo from `RENOVATE_REPOSITORIES` | No dependency PRs |
| Provenance gate blocks a needed release | One-off `provenance-exception` (above). To roll the gate back org-wide, revert the provenance job in the caller | Release ships with the exception recorded |
| A bad change to a reusable workflow | Revert the PR here: callers use `@main`, so the revert applies to the next run everywhere | All repos back on the previous behaviour |
| A bad release image | Do not re-tag. Deploy the previous system version (its lock pins attested digests), then fix forward with a new version | Stage/prod back on the last good digests |

## Evidence

- Per release: GitHub Release assets `sbom-<repo>-<v>.cdx.json` and `provenance-<repo>-<v>.json`, plus attestations (`gh attestation verify oci://ghcr.io/lovablegarden/<repo>:<v> --repo lovablegarden/<repo> --signer-workflow lovablegarden/.github/.github/workflows/release-provenance.yml`).
- Per scan: the run summary and artifacts of each repo's "Security scan" run (90 days).
- Per finding or acceptance: the Jira issue.
- Rollout state: [adopting.md → Rollout status](adopting.md#rollout-status).
