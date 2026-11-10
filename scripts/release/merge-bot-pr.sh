#!/usr/bin/env bash
# Usage: scripts/release/merge-bot-pr.sh <owner/repo> <head-branch> <head-sha>
#
# Squash-merges an open lovablegarden-bot PR once its required checks pass. Called by the `merge`
# job of .github/workflows/gated-release.yml each time a required-check workflow finishes on a PR
# (LG-1219). Handles two kinds of PR and nothing else:
#
#   bump/*                              dependency bumps opened by lovablegarden-bot
#                                       (consumer-bump-bom-version.yml in services,
#                                        consumer-bump-system-lock.yml in lovablegarden-system)
#   release-please--branches--main--*   release PRs opened by release-please
#
# Bumps are merged with a `fix(deps): bump …` subject even if the PR title still says
# `chore: bump …`, because release-please ignores chore: commits. That is what makes a merged bump
# produce the next release with nobody touching it.
#
# Settings (environment):
#   REQUIRED_CHECKS  newline-separated check names, passed on to checks-green.sh (required)
#   BUMP_FILES       ERE every file in a bump PR must match
#                    (default: gradle.properties, which is all a BOM bump changes)
#   RELEASE_FILES    ERE every file in a release PR must match
#                    (default: CHANGELOG.md, the release-please manifest, gradle.properties)
#   COMPONENT_PATHS  for repos with more than one release-please component: lines of
#                    `<component>=<ERE>`. A main commit belongs to a listed component when one of
#                    its files matches that ERE, and to every other component when one of its files
#                    matches none of them. Empty (the default): every commit belongs to every
#                    component.
#   BOT_LOGIN        PR author to trust (default: app/lovablegarden-bot)
#   CHECKS_GH_TOKEN  token for reading check runs, if GH_TOKEN (the App token) can't
#
# Exits 0 without merging when there is nothing to do yet (no PR, stale run, checks still running,
# release PR waiting for release-please to refresh it).
# Exits 1 when the PR looks wrong (unexpected author or files, failed checks), so the run shows red.
set -euo pipefail

REPO="${1:?usage: merge-bot-pr.sh <owner/repo> <head-branch> <head-sha>}"
BRANCH="${2:?usage: merge-bot-pr.sh <owner/repo> <head-branch> <head-sha>}"
SHA="${3:?usage: merge-bot-pr.sh <owner/repo> <head-branch> <head-sha>}"
BOT_LOGIN="${BOT_LOGIN:-app/lovablegarden-bot}"
BUMP_FILES="${BUMP_FILES:-^gradle\.properties$}"
RELEASE_FILES="${RELEASE_FILES:-^(CHANGELOG\.md|\.github/\.release-please-manifest\.json|gradle\.properties)$}"
COMPONENT_PATHS="${COMPONENT_PATHS:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$BRANCH" in
  bump/*)
    KIND=bump
    ALLOWED_FILES="$BUMP_FILES"
    ;;
  release-please--branches--main--*)
    KIND=release
    ALLOWED_FILES="$RELEASE_FILES"
    ;;
  *)
    echo "Not a bot branch this workflow merges: ${BRANCH}"
    exit 0
    ;;
esac

PR_JSON=$(gh pr list -R "$REPO" --head "$BRANCH" --base main --state open --limit 1 \
  --json number,title,author,headRefOid,isDraft,files)
if [ "$(echo "$PR_JSON" | jq 'length')" -eq 0 ]; then
  echo "No open PR for ${BRANCH}; nothing to merge."
  exit 0
fi

NUMBER=$(echo "$PR_JSON" | jq -r '.[0].number')
TITLE=$(echo "$PR_JSON" | jq -r '.[0].title')
AUTHOR=$(echo "$PR_JSON" | jq -r '.[0].author.login')
HEAD_OID=$(echo "$PR_JSON" | jq -r '.[0].headRefOid')
DRAFT=$(echo "$PR_JSON" | jq -r '.[0].isDraft')
echo "PR #${NUMBER} (${KIND}): ${TITLE}"

if [ "$AUTHOR" != "$BOT_LOGIN" ]; then
  echo "::error::PR #${NUMBER} is by ${AUTHOR}, not ${BOT_LOGIN}; not merging."
  exit 1
fi
if [ "$HEAD_OID" != "$SHA" ]; then
  echo "PR #${NUMBER} head is ${HEAD_OID}, this run checked ${SHA}; the run for the new head decides."
  exit 0
fi
if [ "$DRAFT" = "true" ]; then
  echo "PR #${NUMBER} is a draft; not merging."
  exit 0
fi

UNEXPECTED=$(echo "$PR_JSON" | jq -r '.[0].files[].path' | grep -Ev "$ALLOWED_FILES" || true)
if [ -n "$UNEXPECTED" ]; then
  echo "::error::PR #${NUMBER} changes files a ${KIND} PR should not touch; merge it by hand after review:"
  echo "$UNEXPECTED"
  exit 1
fi

# Does a commit with these files (one per line on stdin) belong to component $1?
belongs_to() {
  local component=$1 files own_re="" all_re="" line name re
  files=$(cat)
  [ -n "$COMPONENT_PATHS" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%%=*}; re=${line#*=}
    [ "$name" = "$component" ] && own_re=$re
    all_re="${all_re:+${all_re}|}(${re})"
  done <<< "$COMPONENT_PATHS"
  if [ -n "$own_re" ]; then
    printf '%s\n' "$files" | grep -Eq "$own_re"
  else
    printf '%s\n' "$files" | grep -v '^$' | grep -Evq "$all_re"
  fi
}

if [ "$KIND" = release ]; then
  # Release-please builds a release PR from the main commit it last saw. If a releasable commit for
  # this component has landed on main since, the PR is stale: merging it would tag that commit
  # without its changelog entry (lovablegarden-system v1.0.60 and media bump #229). Release-please
  # refreshes the PR on the next green main run, which pushes a new head and brings this back.
  COMPONENT="${BRANCH##*--components--}"
  STALE=""
  for C in $(gh api "repos/${REPO}/compare/${SHA}...main" --jq '.commits[] | .sha'); do
    MESSAGE=$(gh api "repos/${REPO}/commits/${C}" --jq '.commit.message')
    SUBJECT_LINE=$(printf '%s\n' "$MESSAGE" | head -1)
    if ! printf '%s\n' "$SUBJECT_LINE" | grep -Eq '^(fix|feat|perf|revert)(\([^)]*\))?!?: ' &&
       ! printf '%s\n' "$MESSAGE" | grep -Eqi '^Release-As: '; then
      continue
    fi
    gh api "repos/${REPO}/commits/${C}" --jq '.files[].filename' | belongs_to "$COMPONENT" || continue
    STALE="${STALE}${C:0:7} ${SUBJECT_LINE}"$'\n'
  done
  if [ -n "$STALE" ]; then
    echo "Release PR #${NUMBER} predates releasable commits on main; waiting for release-please to refresh it:"
    printf '%s' "$STALE"
    exit 0
  fi
fi

set +e
# The App token may lack the Checks permission; the workflow passes its GITHUB_TOKEN (checks: read).
GH_TOKEN="${CHECKS_GH_TOKEN:-${GH_TOKEN:-}}" "$SCRIPT_DIR/checks-green.sh" "$REPO" "$SHA"
CHECKS=$?
set -e
case "$CHECKS" in
  0) ;;
  2) echo "Required checks still running on ${SHA}; the next CI completion retries."; exit 0 ;;
  *) echo "::error::Required checks failed on PR #${NUMBER}; not merging."; exit 1 ;;
esac

SUBJECT="$TITLE"
if [ "$KIND" = bump ]; then
  # chore: is not releasable for release-please; fix(deps): is (LG-1219).
  SUBJECT=$(printf '%s' "$TITLE" | sed -E 's/^chore(\([^)]*\))?: /fix(deps): /')
fi
SUBJECT="${SUBJECT} (#${NUMBER})"

echo "Merging PR #${NUMBER} as: ${SUBJECT}"
gh pr merge "$NUMBER" -R "$REPO" --squash --match-head-commit "$SHA" --subject "$SUBJECT" \
  --body "Merged by gated-release.yml after the required checks passed on ${SHA}."
# Delete the head branch through the API: `gh pr merge --delete-branch` also touches the local
# checkout. A failure here leaves a stale branch only, so it does not fail the run.
gh api -X DELETE "repos/${REPO}/git/refs/heads/${BRANCH}" >/dev/null \
  || echo "::warning::Could not delete branch ${BRANCH}"
