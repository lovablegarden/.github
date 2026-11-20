# Node and frontend dependency lifecycle (LG-1223)

Org-wide policy for the Node.js runtime and npm dependencies: the frontend (`lovablegarden/lovablegarden`) and the npm side of `lovablegarden-openapi-spec`. The shared Renovate preset is in [renovate.md](../renovate.md), and the CVE classes and deadlines are in [cve-policy.md](cve-policy.md). Base images and Actions are covered in [lifecycle.md](lifecycle.md). The frontend's repo-specific details (exact pins, framework groups, gates, baselines) are in its own `docs/dependency-lifecycle.md`. Where the two pages differ, this one wins.

Owner: Jessica (platform and frontend). Review this page when a new Node LTS line starts, when a framework the frontend uses ships a major, and at least once a quarter.

## Node.js LTS cadence

Node ships a new even-numbered major every April. It becomes **Active LTS** in October, moves to **Maintenance LTS** a year later and reaches end of life 30 months after it became LTS. Odd-numbered majors never become LTS. Dates come from [endoflife.date/nodejs](https://endoflife.date/nodejs), which the scan's lifecycle check also reads.

| Line | Active LTS from | Maintenance from | End of life | Our use |
| --- | --- | --- | --- | --- |
| 22 | Oct 2024 | Oct 2025 | 30 Apr 2027 | not used |
| **24** | 28 Oct 2025 | 20 Oct 2026 | **30 Apr 2028** | **current line** (frontend 24.14.0) |
| 26 | 28 Oct 2026 | Oct 2027 | 30 Apr 2029 | next line, after Release 1 |

Rules:

1. **Only LTS lines.** Production builds never run on an odd-numbered or a not-yet-LTS major.
2. **Move to the next LTS line within 12 months of it becoming Active LTS**, and always at least 120 days before the running line's end of life. For Node 26 that is by October 2027. Plan the move as a Jira issue in the quarter after Release 1. It's a reviewed change of its own: every pin in one PR, the full gates below, and a test deploy.
3. **Patches and minors within the line** come through Renovate's "Node.js runtime" group (all workflow pins, `.nvmrc` and npm's `packageManager` in one PR). They are reviewed, never auto-merged. Take them at least monthly. A Node security release follows the [CVE policy](cve-policy.md) deadlines like any other finding.
4. **Renovate never proposes a Node major.** The preset disables runtime majors, so the move between lines is always planned work.
5. **Release 1 hold:** the frontend stays on Node 24 until after the 2 Feb 2027 launch. Line 24 is supported until April 2028, so the hold costs nothing.

### One declared version everywhere

Local, CI, the test and production deploys, and the release build use the same Node and npm versions:

| Where | Declared by |
| --- | --- |
| Local | `.nvmrc` (exact version) and `engines` in `package.json` (minimum) |
| CI and deploy workflows | `node-version` pinned to the same exact version (Renovate's regex manager moves them together with `.nvmrc`) |
| Release build ([`frontend-release.yml`](../../.github/workflows/frontend-release.yml)) | The caller's `.nvmrc` when no `node-version` input is passed (since LG-1223). Before that it fell back to the floating `24.x` |
| npm | `packageManager` in `package.json`, exact version |
| Install | `npm ci` only, against `package-lock.json`, the only lock file |

A PR that changes one of these changes all of them.

## Renovate rules for the frontend

The frontend joined the org Renovate run in LG-1495 (Renovate live since LG-1217). Its `renovate.json` extends the org preset (`github>lovablegarden/.github`) and adds one group per framework. Together they give:

| Update | Path | Merge |
| --- | --- | --- |
| **Security fix** (GitHub or OSV advisory) | Opened at once: no schedule, no 3-day release age, `security` label | Reviewed, never auto-merged. Merge once the gates are green, within the [CVE policy](cve-policy.md) deadline for its class |
| **Patch**, other packages | "npm dependencies (non-major)" group, Monday before 07:00 Stockholm, 3-day release age | Auto-merge after the required checks |
| **Minor**, other packages | The same group | Reviewed |
| **Framework or build tool**, any update type: React, React Router, Vite and Vitest, TypeScript, Tailwind, Supabase and TanStack, Node and npm | Its own group, so a framework never hides in the general npm PR | Reviewed, never auto-merged |
| **Major**, any package | Waits for approval on the Dependency Dashboard issue, then gets its own PR, `major` label and a Jira issue | Reviewed, planned work (below) |
| **Lock-file maintenance** | Monthly, on the 1st | Reviewed |
| Generated `@lovablegarden/api-*` clients | Never Renovate: they come from the openapi-spec release | — |

"Required checks" means the `main` rulesets (LG-1225, [operations.md](operations.md)). Until they're enforced in a repo, Renovate's auto-merge only waits for whatever checks GitHub reports. So a patch auto-merge isn't a reason to skip looking at the weekly PRs.

### Gates on every update PR

The same gates run on Renovate PRs as on any frontend PR: `npm ci` (lock-file integrity), lint with the warning baseline, `tsc --noEmit` type check, Vitest, the production build with the i18n check, the static-serving check, Playwright e2e and the security scan. The baselines (lint max-warnings, no skipped unit tests as known failures) are recorded in the frontend doc and can't be raised in an update PR. A new failure fails the PR.

## Majors

A major update is a migration, not a bump. That includes a security fix that only exists in a new major. It goes like this:

1. **Approve it on the Dependency Dashboard** only once a Jira issue exists. The issue lists the breaking changes that affect our code, the files that change and how it will be tested.
2. **Keep the major in its own PR**, and add the companion packages the major needs (resolvers, type packages, plugins) to that PR. Don't merge a bare version bump that compiles but changes runtime behaviour.
3. **Test beyond the gates**: type check and unit tests, plus a browser pass on `test.lovablegarden.com` over every screen the package touches, with valid and invalid input.
4. **If it's a security fix that can't land within its CVE deadline**, keep the Renovate PR open as held, record why in the Jira issue, and either mitigate (the vulnerable code path isn't reachable, or the input is validated elsewhere) or file a dated risk acceptance approved by Jessica ([how](cve-policy.md#risk-acceptance)). A held security PR is never closed without one of those.

**Example: zod 3 → 4 (LG-1500).** zod 4 removed `error.errors`, which `@hookform/resolvers` 3 relies on, so the bump compiles but every form using `zodResolver` throws on invalid input instead of showing errors. It also splits schema input and output types (`.default()`, `z.coerce`) and tightens `.uuid()`, `.email()` and `.url()`. So the work is one PR: zod 4, resolvers 5, the type fixes in the form files and a browser pass over each form. That's planned work under LG-1500, not a Renovate merge.

Majors during the Release 1 freeze (from 25 Jan 2027): only security fixes, and only if the CVE deadline falls before 2 Feb 2027. Everything else waits until after the launch.

## CVE deadlines for npm dependencies

The [CVE policy](cve-policy.md) applies unchanged. Days count from the first scan or advisory that reports the finding. "Fixed" means deployed to production (to `test` before the launch).

| Class | Deadline | How it reaches us |
| --- | --- | --- |
| Known exploited (CISA KEV) | 3 days, mitigated within 24 hours | Nightly scan fails, Highest Jira Bug, Renovate security PR |
| Critical, fix available | 7 days | Jira Bug from the nightly triage, Renovate security PR |
| High | 30 days | Renovate security PR. Jira issue by hand if the PR can't land in time (a major, for example) |
| Medium | 90 days | Renovate security PR or the normal schedule |
| Low | 180 days or the next framework upgrade | Normal schedule |

Frontend specifics:

- **Development-only packages** (Storybook, Vitest, ESLint plugins, build tooling) count at their class too. The build runs them, and the build makes what we ship. Moving one down a class needs a written reason that it never runs in CI or the release build.
- **Deploy**: the frontend deploys through `deploy-prod.yml` (Jessica runs it) at the next 12:00 or 17:00 CET window. If the deadline is shorter, ask for an out-of-window deploy.
- **Private handling**: advisory IDs and details for the frontend go in Jira and in the private repo's PRs, never in this public repo ([cve-policy.md](cve-policy.md#private-handling)).

## Periodic checks

| When | What | Who |
| --- | --- | --- |
| Weekly (Monday) | Merge or triage the Renovate PRs. Check the Dependency Dashboard for majors waiting for approval | Platform |
| Monthly | Lock-file maintenance PR. Node patch/minor PR if one is open | Platform |
| Each frontend release | Bundle size against the last build, e2e on `test`, accessibility and visual checks | Frontend |
| Quarterly | Node end-of-life dates against the table above, browser support, review of this page and the frontend doc | Jessica |

Node 24's end of life is also watched by the nightly scan's lifecycle check ([lifecycle.md](lifecycle.md#end-of-life-monitoring)). It files a Jira Task 30 days before the date. This policy plans the move much earlier, so that Task should never be the first warning.
