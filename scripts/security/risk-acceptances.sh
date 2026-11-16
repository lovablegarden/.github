#!/usr/bin/env bash
# Checks the dated risk acceptances in a .trivyignore (LG-1216 policy, docs/security/cve-policy.md).
#
# Usage: risk-acceptances.sh <path/to/.trivyignore> [today YYYY-MM-DD]
#
# Each accepted ID (a CVE, GHSA, misconfiguration ID or EOL-<product>-<cycle>) needs:
#   - `exp:YYYY-MM-DD` on its line. Trivy stops ignoring the ID on that date, so the finding
#     comes back by itself when the acceptance lapses.
#   - a comment block above it naming a Jira key (rationale, approver and remediation live there).
#
# Writes a Markdown table to stdout, `::warning::` annotations to stderr, and these counts to
# $GITHUB_OUTPUT when set: accepted, expired, expiring, incomplete.
# Exit code: 0, or 1 with STRICT=true when an entry is missing its expiry or Jira key.
set -euo pipefail

file="${1:?usage: risk-acceptances.sh <.trivyignore> [today]}"
today="${2:-$(date -u +%F)}"
soon_days="${EXPIRY_WARN_DAYS:-30}"
strict="${STRICT:-false}"

to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f %F "$1" +%s; }
now=$(to_epoch "$today")

accepted=0 expired=0 expiring=0 incomplete=0
rows=""
comment=""
if [ -f "$file" ]; then
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%$'\r'}"
    case "$line" in
      '' ) comment=""; continue ;;
      '#'* ) comment="$comment ${line#\#}"; continue ;;
    esac
    # shellcheck disable=SC2086
    set -- $line
    id="$1"; shift
    exp=""
    for f in "$@"; do case "$f" in exp:*) exp="${f#exp:}" ;; esac; done
    jira=$(printf '%s' "$comment" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | grep -vE '^(CVE|GHSA|EOL|AVD|DS|KSV)-' | sort -u | paste -sd ' ' - || true)
    status="active"
    problems=""
    if [ -z "$exp" ]; then
      problems="no expiry"
    elif ! e=$(to_epoch "$exp"); then
      problems="bad expiry '$exp'"
    else
      left=$(( (e - now) / 86400 ))
      if [ "$left" -le 0 ]; then
        status="expired"; expired=$((expired + 1))
        echo "::warning file=${file}::Risk acceptance for ${id} expired on ${exp}. Trivy reports it again; fix it or renew the acceptance." >&2
      elif [ "$left" -le "$soon_days" ]; then
        status="expires in ${left} days"; expiring=$((expiring + 1))
        echo "::warning file=${file}::Risk acceptance for ${id} expires on ${exp} (${left} days). Review it (${jira:-no Jira key})." >&2
      fi
    fi
    if [ -z "$jira" ]; then problems="${problems:+$problems, }no Jira key in the comment above"; fi
    if [ -n "$problems" ]; then
      incomplete=$((incomplete + 1))
      echo "::warning file=${file}::Risk acceptance for ${id} is incomplete: ${problems}. See docs/security/cve-policy.md in lovablegarden/.github." >&2
    fi
    [ "$status" = "expired" ] || accepted=$((accepted + 1))
    rows="${rows}| \`${id}\` | ${exp:--} | ${status} | ${jira:--} | ${problems:-ok} |"$'\n'
  done < "$file"
fi

echo "### Risk acceptances (\`$(basename "$file")\`)"
if [ -z "$rows" ]; then
  echo "None. Every finding counts."
else
  echo "Accepted IDs are hidden from the gates until their expiry date. Policy: docs/security/cve-policy.md in lovablegarden/.github."
  echo
  echo "| ID | Expires | Status | Jira | Check |"
  echo "| --- | --- | --- | --- | --- |"
  printf '%s' "$rows"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "accepted=$accepted"
    echo "expired=$expired"
    echo "expiring=$expiring"
    echo "incomplete=$incomplete"
  } >> "$GITHUB_OUTPUT"
fi

if [ "$strict" = "true" ] && [ "$incomplete" -gt 0 ]; then
  echo "::error file=${file}::${incomplete} risk acceptance(s) lack an expiry or a Jira key" >&2
  exit 1
fi
exit 0
