# Renovate (LG-1217)

The shared preset is [`default.json`](../default.json) at the root of this repo. A repo opts in with a `renovate.json` at its root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>lovablegarden/.github"]
}
```

## What the preset does

| Area | Behaviour |
| --- | --- |
| Schedule | Monday before 07:00 (Europe/Stockholm). At most 5 open PRs per repo, at most 2 new PRs an hour. |
| Release age | A version must be 3 days old before Renovate proposes it. |
| Security fixes | Vulnerability alerts (GitHub and OSV) skip the schedule and the release age, get the `security` label, and never auto-merge. Required checks still run. |
| GitHub Actions | Pinned to commit SHA with the version in a comment. Grouped into one PR. Non-major updates auto-merge after required checks. |
| Gradle wrapper | Own PR, never auto-merged. |
| Spring Boot | Plugin, starters and `io.spring.dependency-management` in one group, never auto-merged. |
| Other Gradle/Maven, npm | Non-major updates grouped per manager. Patch updates auto-merge; minor updates need a review. |
| Majors | Separate PR, only after approval on the Dependency Dashboard, never auto-merged. Java and Node runtime majors are not proposed (planned work, LG-1222). |
| Runtimes and frameworks | Spring Boot, React, TypeScript, Vite, Node, Temurin, PostgreSQL and Flyway never auto-merge, whatever the update type. |
| Internal artifacts | Disabled: `com.lovablegarden`, `se.lovablegarden.api`, `@lovablegarden/*`, `ghcr.io/lovablegarden/*` and the org reusable workflows. The consumer-bump bot owns `lovablegardenBomVersion` and the system lock; API clients come through the BOM; reusables stay on `@main`. |
| Lock files | Monthly lock-file maintenance PR, not auto-merged. |
| Dashboard | Each repo gets a "Dependency Dashboard" issue listing pending, rate-limited, awaiting-approval and ignored updates. |

Auto-merge uses GitHub's native auto-merge, so it only happens once the branch protection's required checks pass.

## How it runs (self-hosted)

Renovate runs here as the scheduled workflow [`renovate.yml`](../.github/workflows/renovate.yml), not as the Mend-hosted app (decided 2026-11-13). It uses the existing `lovablegarden-bot` GitHub App (`LOVABLEGARDEN_BOT_APP_ID`, `LOVABLEGARDEN_BOT_PRIVATE_KEY`) and the `ghcr.io/renovatebot/renovate:41` image.

| Setting | Value |
| --- | --- |
| Repos | `RENOVATE_REPOSITORIES` in the workflow. Pilot: `lovablegarden-system`, `lovablegarden-security-common`. |
| Opt-in | `requireConfig=required`, onboarding off: a repo without `renovate.json` is skipped, and Renovate never opens onboarding PRs. |
| Scheduled runs | Hourly on weekdays, only while the Actions variable `RENOVATE_ENABLED` is `true`. The preset's schedule decides when PRs open. |
| Manual run | **Actions → Renovate → Run workflow**. `dry_run` (default on) only logs what would happen. |

**App permissions needed before the first real run** (Jessica grants them in the GitHub App settings): Contents, Pull requests, Issues (Dependency Dashboard) and Workflows (Renovate updates `.github/workflows/*`) set to **Read and write**, and Checks and Commit statuses set to **Read**.

**Turning it on:**

1. Grant the app permissions above and accept the permission change for the org installation.
2. Run **Renovate** by hand with `dry_run` on, and check the log for both pilot repos.
3. Set the Actions variable `RENOVATE_ENABLED` = `true` (org or this repo).

**Turning it off quickly:** set `RENOVATE_ENABLED` to `false` (or delete it).

## Rolling out

1. Pilot: lovablegarden-system and one backend repo, lovablegarden-security-common (Block A, R1 round). The frontend and other services come later, one PR each, adding the repo to `RENOVATE_REPOSITORIES` too.
2. Check the first PRs: labels, grouping, and that nothing outside patch/actions auto-merged.
3. Add `renovate.json` to the remaining active repos, one PR each.

## Turning it off

| Scope | How |
| --- | --- |
| One update | Close the PR. Renovate won't propose that version again. Or tick it as ignored on the dashboard. |
| One package | Add a `packageRules` entry with `"enabled": false` to the repo's `renovate.json`. |
| Auto-merge for one repo | Add `"automerge": false` at the top level and in a final `packageRules` entry matching `"*"`. |
| One repo | Set `"enabled": false` in its `renovate.json`, or delete the file. |
| Everything | Set `RENOVATE_ENABLED` to `false`. To undo config, revert the preset change here (all repos read it from `main`). |

To roll back a merged update, revert its PR. Renovate then sees the older version and proposes the update again on the next schedule unless you ignore it on the dashboard.
