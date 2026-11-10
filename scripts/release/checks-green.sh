#!/usr/bin/env bash
# Usage: REQUIRED_CHECKS=$'name 1\nname 2' scripts/release/checks-green.sh <owner/repo> <sha>
#
# Decides whether the required checks on a commit have passed. Used by the release gate and the
# bot PR auto-merge in .github/workflows/gated-release.yml (LG-1219).
#
# REQUIRED_CHECKS: newline-separated check-run names, exactly as GitHub shows them on the commit
# (a job in a called workflow shows as "<caller job id> / <job name>", e.g. "ci / Build Application").
#
# Exit codes:
#   0  every required check has a completed, successful run
#   1  a required check failed, was cancelled or timed out
#   2  a required check is missing or still running (try again on the next workflow_run event)
#
# Only the required checks count. The release workflow adds its own check runs to the same commit
# while it runs, so "every check on the commit" would never be green.
set -euo pipefail

REPO="${1:?usage: checks-green.sh <owner/repo> <sha>}"
SHA="${2:?usage: checks-green.sh <owner/repo> <sha>}"

CHECKS=()
while IFS= read -r c; do
  [ -n "$c" ] && CHECKS+=("$c")
done < <(printf '%s\n' "${REQUIRED_CHECKS:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ "${#CHECKS[@]}" -eq 0 ]; then
  echo "::error::REQUIRED_CHECKS is empty; refusing to treat a commit as green without any check."
  exit 1
fi

# filter=latest (the API default) returns only the newest run per check name, so a re-run that
# passed replaces the failed attempt.
RUNS=$(gh api --paginate "repos/${REPO}/commits/${SHA}/check-runs?filter=latest&per_page=100" \
  --jq '.check_runs[] | [.name, .status, (.conclusion // "")] | @tsv')

result=0
for name in "${CHECKS[@]}"; do
  line=$(printf '%s\n' "$RUNS" | awk -F'\t' -v n="$name" '$1 == n' | head -1)
  if [ -z "$line" ]; then
    echo "pending  ${name}: no run yet"
    [ "$result" -eq 1 ] || result=2
    continue
  fi
  status=$(printf '%s' "$line" | cut -f2)
  conclusion=$(printf '%s' "$line" | cut -f3)
  if [ "$status" != "completed" ]; then
    echo "pending  ${name}: ${status}"
    [ "$result" -eq 1 ] || result=2
  elif [ "$conclusion" = "success" ]; then
    echo "ok       ${name}"
  else
    echo "failed   ${name}: ${conclusion}"
    result=1
  fi
done
exit "$result"
