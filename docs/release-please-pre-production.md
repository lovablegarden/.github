# release-please — pre-production policy

LovableGarden is not released to end users yet. Service and system repos use **patch-only** semver until public launch.

## Config

Each pilot repo sets in `.github/release-please-config.json`:

```json
"versioning": "always-bump-patch"
```

This makes release-please bump **patch only**, even for `feat:` or breaking commits. Commit convention still prefers `fix:` for release-worthy infra work; see the global **lovablegarden-infra** Cursor skill.

Non-release commit types (`chore`, `docs`, `ci`, …) are `hidden: true` in `changelog-sections` so they do not open a Release PR when they are the only changes since the last tag.

Copy from [templates/release-please-config.pre-production.json](../templates/release-please-config.pre-production.json) and set `component`.

## Public launch checklist

When the product is live for users:

1. Remove `"versioning": "always-bump-patch"` from each repo (defaults to standard semver).
2. Keep `changelog-sections` hidden flags for `chore`/`docs`/`ci` if desired.
3. Update `lovablegarden-system/docs/pipelines/release-flow.md` phase note.
4. Update the **lovablegarden-infra** skill pre-production section.

Standard semver after launch:

| Commit | Bump |
|--------|------|
| `feat:` | minor |
| `fix:` | patch |
| `BREAKING CHANGE` / `feat!:` | major |

## Gated release and auto-merge (LG-1219)

Every repo runs release-please through [`gated-release.yml`](../.github/workflows/gated-release.yml),
called from its own `.github/workflows/release-please.yml`
([caller template](../templates/gated-release-caller.yml)):

- release-please runs only when the repo's required checks passed on the current `main` commit;
- lovablegarden-bot `bump/*` PRs are retitled `fix(deps): …` and, like release PRs, squash-merged
  once the required checks pass on them;
- a release PR waits while `main` has a releasable commit it doesn't include yet (race guard).

Releasable: `fix:` (including the bot's `fix(deps):` bumps), `feat:`, `perf:`, `revert:`, or any
commit with a `Release-As:` footer. `chore`/`docs`/`ci`/`build`/`refactor`/`test` ride along in the
next release. Logic: `scripts/release/`, tests: `tests/gated-release/run-tests.sh`.
Full flow: `lovablegarden-system/docs/pipelines/release-flow.md` ("Org-wide gated release").
