# Bugs: Jira first, GitHub for intake (LG-1221)

**Jira is the bug record.** Every bug we work on is exactly one Jira **Bug** in project LG, and Jira decides its priority, status, release impact and any cross-repository work. GitHub issues are only a convenient way to *report* a bug. Nothing is synchronised both ways; the one automatic link back is closing the GitHub issue when its Jira bug is Done.

## Flow

```
GitHub issue (bug form)  ──triage──▶  bug:accepted  ──bug intake──▶  one Jira Bug (label gh-<repo>-<n>)
        ▲                                                                   │
        └──── closed with a comment when the Jira Bug is Done ◀── sync ─────┘
                                                       Jira: fix PR(s) → release → verified on a deployed env → Done
```

1. **Report.** Anyone who can open issues uses the **Bug report** form. It is the org default ([`.github/ISSUE_TEMPLATE`](../.github/ISSUE_TEMPLATE/bug_report.yml)) for every repo that has no form of its own. Blank issues are off. The form asks for what happened, steps, expected result, impact, environment, time and version, and warns against secrets, personal data and vulnerability disclosure. New reports get the labels `bug` and `bug:triage`.
   Bugs found internally go straight into Jira; they don't need a GitHub issue.
2. **Triage** (owner below). Within the response time:
   - **Security problem** reported publicly by mistake: hide the content, ask the reporter to use [private vulnerability reporting](../SECURITY.md), and handle it under the [CVE policy](security/cve-policy.md).
   - **Personal data or secrets in the report:** edit them out (and rotate a leaked secret) before anything else. Bug intake copies the report text into Jira.
   - **Duplicate of an existing Jira bug:** link it (step 3, with `jira-key`). **Duplicate GitHub issue:** close it as a duplicate of the other issue.
   - **Not a bug, can't reproduce, or out of scope:** label `bug:declined`, explain, close.
   - **Accepted:** add the label `bug:accepted`.
3. **Bug intake** ([`bug-intake.yml`](../.github/workflows/bug-intake.yml)) runs when `bug:accepted` is added:
   - It searches Jira for the label `gh-<repo>-<number>`. If an issue has it, that one is reused, so re-labelling never creates a second Bug.
   - Otherwise it creates a Jira **Bug** with that label plus `github-intake` and `repo-<repo>`. The summary is `[GitHub <repo>#<n>] <title>`, and the description links the issue and quotes the report as plain text.
   - To link an **existing** Jira issue instead (the bug is already known), run the repo's **Bugs** workflow by hand with the issue number and `jira-key`. It adds the labels to that Jira issue and comments there.
   - The GitHub issue gets the label `jira:<KEY>` and one comment naming the key, saying that merging a fix does not close it.
4. **Work happens in Jira.** Priority, fix version, sprint, status and the repositories involved are set there. Branches and PRs name the key (below).
5. **Done means verified.** A merged PR or a release does **not** make a bug Done. The Jira Bug moves to Done only after the fix is verified on a deployed environment (stage for most fixes; prod when the bug was only seen there), with the evidence in a Jira comment. Moving to Done is the product owner's call.
6. **Closing on GitHub.** Every day the **Bugs** workflow reads the Jira status of each open `bug:accepted` issue that has a `jira:` label. When the Jira Bug is Done, it closes the GitHub issue as completed, with a comment naming the key, the resolution and the fix version. Comments are never copied in either direction.

## Severity and priority

The form's **impact** answer is the reporter's view and is quoted in Jira. Triage sets the Jira priority:

| Jira priority | Meaning | Target |
| --- | --- | --- |
| Highest | Outage, data loss or corruption, a security impact, or prod unusable for most users | Start now; fix or mitigate within 1 working day |
| High | A main feature broken with no workaround | Next release |
| Medium | Broken with a workaround, or a secondary feature | Planned in the release it affects |
| Low | Cosmetic, text, layout | When convenient |

Before launch, **release impact** is recorded on the Jira Bug (fix version and, if it blocks Release 1, the label `release-1`). The go/no-go checklist counts open Highest and High bugs.

## Ownership and response times

| What | Who | Expectation |
| --- | --- | --- |
| Triage of new GitHub reports | Jessica Backvall (product owner), or whoever she delegates triage to | First response (accepted, declined or a question) within **3 working days** |
| Jira priority, release impact, Done | Jessica Backvall | As above; Done only after deployed verification |
| Fix | The repo's owner for the sprint (Jira assignee) | Per the priority table |
| Security reports | [SECURITY.md](../SECURITY.md) | Acknowledge in 3 working days, plan in 10 |

## Branches, PRs and releases link to Jira

- Branch: `<type>/lg-<number>-<slug>` (for example `fix/lg-1440-patch-status`).
- PR title (and therefore the squash commit and the release notes): a conventional commit with the key, for example `fix(tasks): keep status on PATCH (LG-1440)`. The org default [PR template](../.github/pull_request_template.md) asks for it.
- The reusable [`jira-key.yml`](../.github/workflows/jira-key.yml) check fails a PR whose title, branch and body have no `LG-<number>`. It exempts bot PRs (release-please, bumps, Renovate). It isn't a required ruleset check; repos opt in.
- release-please changelogs carry the PR titles, so each release lists its Jira keys.

## Privacy rules for reports

- The form warns reporters; triage removes secrets and personal data before acceptance, because the report text is copied into Jira.
- Never paste prod data, user data, tokens or full request logs into a GitHub issue. Request IDs (`X-Request-Id`) and timestamps are enough to find logs.
- Only the `.github` repo is public. Issues in the private and internal repos are visible to the org only, but the same rules apply.

## Adopting in a repo

1. Issue forms and the PR template come from this repo automatically, unless the repo has its own `.github/ISSUE_TEMPLATE` or `pull_request_template.md`.
2. Create the labels `bug`, `bug:triage`, `bug:accepted` and `bug:declined`. Bug intake creates the `jira:<KEY>` labels itself.
3. Add a caller: copy [`bugs.yml`](../.github/workflows/bugs.yml), but point `uses:` at `lovablegarden/.github/.github/workflows/bug-intake.yml@main` and drop `tooling-ref`. It needs `issues: write` and the org Jira secrets (`secrets: inherit`). The full caller is in the header of `bug-intake.yml`.
4. Optional: add the [`jira-key.yml`](../.github/workflows/jira-key.yml) PR check.

Without the Jira secrets or the `JIRA_BASE_URL` variable, bug intake is a dry run: it shows in the job summary what it would do and changes nothing.
