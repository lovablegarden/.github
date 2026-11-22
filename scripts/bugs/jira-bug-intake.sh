#!/usr/bin/env bash
# Jira-first bug intake for GitHub issues (LG-1221). Jira is the bug record; GitHub is only intake.
#
#   link  An accepted GitHub bug gets exactly one Jira Bug. If an issue with the label
#         gh-<repo>-<number> exists it is reused. With JIRA_KEY set, that existing Jira issue is
#         linked instead of creating one (a duplicate of a bug Jira already has). The GitHub issue
#         gets the label jira:<KEY> and one comment naming it.
#   sync  For every open GitHub issue labelled bug:accepted with a jira:<KEY> label, read the Jira
#         status. When the Jira issue is Done (status category "done"), comment once and close the
#         GitHub issue as completed. Nothing else is mirrored: no comment sync either way.
#
# Env (link): REPO (owner/name), ISSUE_NUMBER, ISSUE_TITLE, ISSUE_URL, ISSUE_BODY_FILE, optional JIRA_KEY
# Env (sync): REPO
# Jira:       JIRA_BASE_URL, JIRA_USER_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT (default LG).
#             Without them this is a dry run that prints what it would do and changes nothing.
# GitHub:     gh with GH_TOKEN (issues: write). DRY_RUN=true also skips the GitHub writes.
set -euo pipefail

mode=${1:-}
project="${JIRA_PROJECT:-LG}"
repo_name=${REPO#*/}
dry=${DRY_RUN:-false}
if [ -z "${JIRA_BASE_URL:-}" ] || [ -z "${JIRA_USER_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  dry=true
  echo "Dry run: Jira is not configured (JIRA_BASE_URL variable, JIRA_USER_EMAIL and JIRA_API_TOKEN secrets); nothing is changed."
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The token goes into a curl config file, never onto the command line.
if [ "$dry" != true ]; then
  umask 077
  printf 'user = "%s:%s"\n' "${JIRA_USER_EMAIL:-}" "${JIRA_API_TOKEN:-}" > "$work/curl.cfg"
fi
jira() { # METHOD PATH [JSON-FILE]
  local args=(-fsS --max-time 30 -K "$work/curl.cfg" -X "$1" -H 'Accept: application/json' "${JIRA_BASE_URL%/}$2")
  [ -n "${3:-}" ] && args+=(-H 'Content-Type: application/json' --data "@$3")
  curl "${args[@]}"
}
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; echo "$1"; }

link() {
  : "${REPO:?}" "${ISSUE_NUMBER:?}" "${ISSUE_TITLE:?}" "${ISSUE_URL:?}"
  local gh_label="gh-${repo_name}-${ISSUE_NUMBER}" key='' action
  if [ -n "${JIRA_KEY:-}" ]; then
    [[ "$JIRA_KEY" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || { echo "::error::JIRA_KEY '$JIRA_KEY' is not a Jira key" >&2; exit 2; }
  fi
  if [ "$dry" = true ]; then
    summary "Would link ${REPO}#${ISSUE_NUMBER} to ${JIRA_KEY:-a new or existing $project Bug labelled $gh_label}."
    return 0
  fi

  jq -n --arg jql "project = \"${project}\" AND labels = \"${gh_label}\" ORDER BY created ASC" \
    '{jql: $jql, fields: ["status"], maxResults: 1}' > "$work/q.json"
  key=$(jira POST /rest/api/3/search/jql "$work/q.json" | jq -r '.issues[0].key // empty')

  if [ -n "$key" ]; then
    action="already linked"
    if [ -n "${JIRA_KEY:-}" ] && [ "$JIRA_KEY" != "$key" ]; then
      echo "::error::${REPO}#${ISSUE_NUMBER} is already linked to $key; unlink it in Jira (label $gh_label) before linking $JIRA_KEY." >&2
      exit 1
    fi
  elif [ -n "${JIRA_KEY:-}" ]; then
    key=$JIRA_KEY
    jq -n --arg l "$gh_label" '{update: {labels: [{add: $l}, {add: "github-intake"}]}}' > "$work/u.json"
    jira PUT "/rest/api/2/issue/${key}" "$work/u.json" >/dev/null
    jq -n --arg u "$ISSUE_URL" --arg r "$REPO#$ISSUE_NUMBER" \
      '{body: ("GitHub report linked: [\($r)|\($u)]. Jira stays the bug record.\n\nPosted by Claude Code bug intake (LG-1221)")}' > "$work/c.json"
    jira POST "/rest/api/2/issue/${key}/comment" "$work/c.json" >/dev/null
    action="linked existing"
  else
    # The report is untrusted text from the reporter: it goes into the description as a quoted block only.
    local body=''
    [ -n "${ISSUE_BODY_FILE:-}" ] && [ -f "$ISSUE_BODY_FILE" ] && body=$(head -c 20000 "$ISSUE_BODY_FILE")
    jq -n --arg p "$project" --arg t "$ISSUE_TITLE" --arg r "$REPO#$ISSUE_NUMBER" --arg u "$ISSUE_URL" \
      --arg b "$body" --arg gl "$gh_label" --arg rl "repo-$repo_name" '
      {fields: {project: {key: $p}, issuetype: {name: "Bug"},
        summary: ("[GitHub " + $r + "] " + $t)[0:250],
        labels: ["github-intake", $gl, $rl],
        description: ("Reported on GitHub: [" + $r + "|" + $u + "]. Accepted in triage; Jira is the bug record (LG-1221).\nPriority, release impact and status are set here, not on GitHub.\n\n{noformat}\n" + $b + "\n{noformat}\n\nCreated by bug intake (LG-1221). Posted by Claude Code")}}' > "$work/c.json"
    key=$(jira POST /rest/api/2/issue "$work/c.json" | jq -r '.key')
    action="created"
  fi

  if [ "$dry" != true ] && [ "${DRY_RUN:-false}" != true ]; then
    gh label create "jira:${key}" --repo "$REPO" --color 0052CC --description "Jira bug record" >/dev/null 2>&1 || true
    gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --add-label "jira:${key}" >/dev/null
    if ! gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json comments --jq '.comments[].body' | grep -q "<!-- lg-bug-intake:${key} -->"; then
      gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$(printf '%s\n\n%s\n%s' \
        "Thanks, this is accepted as a bug and tracked in Jira as **${key}**. Priority, status and the release it ships in are decided there; this issue is closed when ${key} is verified on a deployed environment and Done." \
        "Merging a fix doesn't close it." "<!-- lg-bug-intake:${key} -->")" >/dev/null
    fi
  fi
  summary "${REPO}#${ISSUE_NUMBER}: ${action} ${key}"
}

sync() {
  : "${REPO:?}"
  local n=0 closed=0
  gh issue list --repo "$REPO" --state open --label bug:accepted --limit 200 --json number,labels \
    --jq '.[] | [.number, ([.labels[].name | select(startswith("jira:"))][0] // "")] | @tsv' > "$work/open.tsv"
  while IFS=$'\t' read -r num label; do
    n=$((n + 1))
    [ -z "$label" ] && { echo "#${num}: accepted but not linked yet (no jira: label)"; continue; }
    key=${label#jira:}
    if [ "$dry" = true ]; then echo "#${num}: would check ${key}"; continue; fi
    if ! st=$(jira GET "/rest/api/2/issue/${key}?fields=status,resolution,fixVersions"); then
      echo "::warning::#${num}: could not read ${key}"; continue
    fi
    [ "$(jq -r '.fields.status.statusCategory.key' <<<"$st")" = "done" ] || continue
    res=$(jq -r '[.fields.resolution.name // empty, (.fields.fixVersions // [] | map(.name) | join(", ") | select(. != "") | "fix version " + .)] | join(", ")' <<<"$st")
    if [ "${DRY_RUN:-false}" != true ]; then
      gh issue close "$num" --repo "$REPO" --reason completed \
        --comment "${key} is Done in Jira${res:+ ($res)}: the fix is verified on a deployed environment. Closing. If it still happens, open a new bug report and mention ${key}." >/dev/null
    fi
    closed=$((closed + 1)); echo "#${num}: closed (${key} Done)"
  done < "$work/open.tsv"
  summary "Bug sync ${REPO}: ${n} open accepted issue(s), ${closed} closed."
}

case "$mode" in
  link) link ;;
  sync) sync ;;
  *) echo "usage: $0 link|sync" >&2; exit 2 ;;
esac
