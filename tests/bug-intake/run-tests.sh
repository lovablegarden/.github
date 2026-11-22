#!/usr/bin/env bash
# Tests for scripts/bugs/jira-bug-intake.sh (LG-1221). No network: curl and gh are stubbed.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
s="$(cd "$here/../.." && pwd)/scripts/bugs/jira-bug-intake.sh"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
fresh() { FIX=$(mktemp -d); mkdir -p "$FIX/jira"; export FIX; printf 'It breaks.\n{noformat} injected' > "$FIX/body.txt"; }
export PATH="$here/stubs:$PATH"
jira_env=(JIRA_BASE_URL=https://jira.test JIRA_USER_EMAIL=bot@example.test JIRA_API_TOKEN=test-token)
issue_env=(REPO=lovablegarden/lovablegarden-example ISSUE_NUMBER=7 "ISSUE_TITLE=Task comes back" ISSUE_URL=https://github.test/i/7)

echo "# link"
fresh
out=$(env "${issue_env[@]}" ISSUE_BODY_FILE="$FIX/body.txt" bash "$s" link 2>&1); rc=$?
check "dry run without Jira settings changes nothing" '[ $rc = 0 ] && grep -q "Dry run" <<<"$out" && [ ! -e "$FIX/jira-calls.log" ] && [ ! -e "$FIX/gh-calls.log" ]'

out=$(env "${jira_env[@]}" "${issue_env[@]}" ISSUE_BODY_FILE="$FIX/body.txt" bash "$s" link 2>&1); rc=$?
check "creates one Jira Bug" '[ $rc = 0 ] && grep -q "created LG-200" <<<"$out" && [ "$(ls "$FIX/jira" | grep -c .)" = 1 ]'
check "Bug type and intake labels" 'jq -e ".fields.issuetype.name == \"Bug\" and (.fields.labels | index(\"gh-lovablegarden-example-7\") and index(\"github-intake\") and index(\"repo-lovablegarden-example\"))" "$FIX/jira/LG-200.json" >/dev/null'
check "report quoted in the description" 'jq -r .fields.description "$FIX/jira/LG-200.json" | grep -q "It breaks."'
check "GitHub issue labelled and commented" 'grep -q "issue edit 7 .*--add-label jira:LG-200" "$FIX/gh-calls.log" && grep -q "issue comment 7" "$FIX/gh-calls.log"'

: > "$FIX/gh-calls.log"
out=$(env "${jira_env[@]}" "${issue_env[@]}" GH_COMMENTS='<!-- lg-bug-intake:LG-200 -->' bash "$s" link 2>&1); rc=$?
check "second run reuses the same Bug (exactly one)" '[ $rc = 0 ] && grep -q "already linked LG-200" <<<"$out" && [ "$(ls "$FIX/jira" | grep -c .)" = 1 ]'
check "no duplicate comment" '! grep -q "issue comment" "$FIX/gh-calls.log"'

out=$(env "${jira_env[@]}" "${issue_env[@]}" JIRA_KEY=LG-999 bash "$s" link 2>&1); rc=$?
check "refuses to link a second Jira issue" '[ $rc = 1 ] && grep -q "already linked to LG-200" <<<"$out"'

fresh
echo '{"key":"LG-50","fields":{"labels":["bug"],"status":{"statusCategory":{"key":"indeterminate"}}}}' > "$FIX/jira/LG-50.json"
out=$(env "${jira_env[@]}" "${issue_env[@]}" JIRA_KEY=LG-50 bash "$s" link 2>&1); rc=$?
check "links an existing Jira issue instead of creating" '[ $rc = 0 ] && grep -q "linked existing LG-50" <<<"$out" && [ "$(ls "$FIX/jira" | grep -c .)" = 1 ]'
check "existing issue gets the intake label and a signed comment" 'jq -e ".fields.labels | index(\"gh-lovablegarden-example-7\")" "$FIX/jira/LG-50.json" >/dev/null && grep -q "Posted by Claude Code" "$FIX/jira-comment-LG-50.json"'
out=$(env "${jira_env[@]}" "${issue_env[@]}" 'JIRA_KEY=LG-1; rm -rf /' bash "$s" link 2>&1); rc=$?
check "rejects a malformed Jira key" '[ $rc = 2 ]'

echo "# sync"
fresh
echo '{"key":"LG-60","fields":{"status":{"statusCategory":{"key":"done"}},"resolution":{"name":"Done"},"fixVersions":[{"name":"1.0.119"}]}}' > "$FIX/jira/LG-60.json"
echo '{"key":"LG-61","fields":{"status":{"statusCategory":{"key":"indeterminate"}}}}' > "$FIX/jira/LG-61.json"
cat > "$FIX/gh-open.json" <<'J'
[{"number":1,"labels":[{"name":"bug:accepted"},{"name":"jira:LG-60"}]},
 {"number":2,"labels":[{"name":"bug:accepted"},{"name":"jira:LG-61"}]},
 {"number":3,"labels":[{"name":"bug:accepted"}]},
 {"number":4,"labels":[{"name":"bug:accepted"},{"name":"jira:LG-404"}]}]
J
out=$(env "${jira_env[@]}" REPO=lovablegarden/lovablegarden-example bash "$s" sync 2>&1); rc=$?
check "sync exit 0" '[ $rc = 0 ]'
check "closes only the issue whose Jira bug is Done" '[ "$(grep -c "issue close" "$FIX/gh-calls.log")" = 1 ] && grep -q "issue close 1 .*--reason completed" "$FIX/gh-calls.log"'
check "close comment names key and fix version" 'grep -q "LG-60 is Done in Jira (Done, fix version 1.0.119)" "$FIX/gh-calls.log"'
check "unlinked accepted issue reported" 'grep -q "#3: accepted but not linked" <<<"$out"'
check "unreadable Jira issue only warns" 'grep -q "could not read LG-404" <<<"$out"'
check "summary counts" 'grep -q "4 open accepted issue(s), 1 closed" <<<"$out"'

exit $fail
