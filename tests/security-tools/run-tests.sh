#!/usr/bin/env bash
# Tests for scripts/security/*.sh (LG-1216, LG-1224). No network: curl is stubbed
# (tests/security-tools/stubs/curl plays Jira and endoflife.date).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
s="$root/scripts/security"
fx="$here/fixtures"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
fresh() { FIX=$(mktemp -d); mkdir -p "$FIX/state"; cp -r "$fx/eol" "$FIX/eol"; export FIX; }
export PATH="$here/stubs:$PATH"

echo "# risk-acceptances.sh"
fresh
cat > "$FIX/ti" <<'T'
# Risk acceptance (LG-1216 policy), LG-1458. Accepted 2026-11-14, review by 2027-03-31.
CVE-2026-22732 exp:2027-03-31
CVE-2026-47884 exp:2027-03-31

CVE-2024-38821
T
out=$(GITHUB_OUTPUT="$FIX/o" bash "$s/risk-acceptances.sh" "$FIX/ti" 2026-11-16 2>"$FIX/err"); rc=$?
check "exit 0 by default" '[ $rc = 0 ]'
check "both dated acceptances active" '[ "$(grep -c "| active | LG-1216 LG-1458 | ok |" <<<"$out")" = 2 ]'
check "entry without expiry or key is incomplete" 'grep -q "CVE-2024-38821.*no expiry, no Jira key" <<<"$out"'
check "outputs counted" 'grep -qx accepted=3 "$FIX/o" && grep -qx incomplete=1 "$FIX/o" && grep -qx expired=0 "$FIX/o"'
STRICT=true bash "$s/risk-acceptances.sh" "$FIX/ti" 2026-11-16 >/dev/null 2>&1; rc=$?
check "STRICT fails on an incomplete entry" '[ $rc = 1 ]'
out=$(bash "$s/risk-acceptances.sh" "$FIX/ti" 2027-03-10 2>"$FIX/err")
check "warns 21 days before expiry" 'grep -q "expires on 2027-03-31 (21 days)" "$FIX/err"'
out=$(GITHUB_OUTPUT="$FIX/o2" bash "$s/risk-acceptances.sh" "$FIX/ti" 2027-03-31 2>"$FIX/err")
check "expired on the review date" 'grep -qx expired=2 "$FIX/o2" && grep -q "expired on 2027-03-31" "$FIX/err"'
out=$(bash "$s/risk-acceptances.sh" "$FIX/missing" 2>&1); rc=$?
check "no .trivyignore is fine" '[ $rc = 0 ] && grep -q "None" <<<"$out"'

echo "# lifecycle.sh"
fresh
out=$(cd "$FIX" && ENDOFLIFE_API=https://eol.test TODAY=2026-11-16 LIFECYCLE_JSON="$FIX/lc.json" GITHUB_OUTPUT="$FIX/o" bash "$s/lifecycle.sh" "$fx/repo" 2>"$FIX/err"); rc=$?
check "exit 0" '[ $rc = 0 ]'
check "unpinned action found" 'jq -e "any(.[]; .id == \"PIN-action-docker/login-action\" and .status == \"unpinned\")" "$FIX/lc.json" >/dev/null'
check "pinned, local and org reusable actions exempt" '[ "$(jq "[.[] | select(.kind == \"pin\" and (.ref | test(\"checkout|local|lovablegarden\")))] | length" "$FIX/lc.json")" = 0 ]'
check "unpinned base image found, digest-pinned and stage aliases skipped" '[ "$(jq -c "[.[] | select(.id | startswith(\"PIN-image\")) | .ref]" "$FIX/lc.json")" = "[\"eclipse-temurin:21-jre-alpine\"]" ]'
check "Spring Boot 3.2 EOL accepted via .trivyignore" 'jq -e "any(.[]; .id == \"EOL-spring-boot-3.2\" and .status == \"accepted\")" "$FIX/lc.json" >/dev/null'
check "Temurin 21 supported" 'jq -e "any(.[]; .id == \"EOL-eclipse-temurin-21\" and .status == \"supported\")" "$FIX/lc.json" >/dev/null'
check "counts: 0 eol, 2 unpinned" 'grep -qx eol=0 "$FIX/o" && grep -qx unpinned=2 "$FIX/o"'
out=$(ENDOFLIFE_API=https://eol.test TODAY=2026-11-16 LIFECYCLE_JSON="$FIX/lci.json" bash "$s/lifecycle.sh" "$fx/repo" "$fx/trivy-image.json" 2>"$FIX/err")
check "image mode: Alpine 3.19 EOL" 'jq -e "any(.[]; .id == \"EOL-alpine-3.19\" and .status == \"eol\")" "$FIX/lci.json" >/dev/null'
echo '{"Metadata":{"OS":{"Family":"debian","Name":"9.13"}}}' > "$FIX/debian.json"
out=$(ENDOFLIFE_API=https://eol.test TODAY=2026-11-16 LIFECYCLE_JSON="$FIX/lcu.json" bash "$s/lifecycle.sh" "$fx/repo" "$FIX/debian.json" 2>"$FIX/err"); rc=$?
check "unknown cycle on endoflife.date only warns" '[ $rc = 0 ] && grep -q "no data for debian 9" "$FIX/err"'

echo "# cve-triage.sh"
fresh
env_common=(REPO=lovablegarden/lovablegarden-example TODAY=2026-11-16 TRIVY_JSON="$fx/trivy-image.json" LIFECYCLE_JSON="$fx/lifecycle.json" KEV_JSON="$fx/kev.json" RUN_URL=https://github.test/run/1)
out=$(env "${env_common[@]}" GITHUB_OUTPUT="$FIX/o" bash "$s/cve-triage.sh" 2>"$FIX/err"); rc=$?
check "dry run without Jira settings" 'grep -q "Dry run" <<<"$out" && [ ! -s "$FIX/calls.log" ]'
check "3 candidates: fixable CRITICAL, KEV, EOL (not HIGH, not unfixed CRITICAL)" 'grep -qx candidates=3 "$FIX/o" && ! grep -q "CVE-2099-0002\|CVE-2099-0003" <<<"$out"'
check "same CVE+package on two targets is one finding" '[ "$(grep -c "CVE-2099-0001" <<<"$out")" = 1 ]'
check "KEV finding fails the run (notification)" '[ $rc = 1 ] && grep -q "known-exploited" "$FIX/err"'
out=$(env "${env_common[@]}" FAIL_ON_KEV=false bash "$s/cve-triage.sh" 2>/dev/null); rc=$?
check "FAIL_ON_KEV=false exits 0" '[ $rc = 0 ]'

jira_env=(JIRA_BASE_URL=https://jira.test JIRA_USER_EMAIL=bot@example.test JIRA_API_TOKEN=test-token FAIL_ON_KEV=false)
out=$(env "${env_common[@]}" "${jira_env[@]}" GITHUB_OUTPUT="$FIX/o" bash "$s/cve-triage.sh" 2>"$FIX/err"); rc=$?
check "first run creates 3 issues" '[ $rc = 0 ] && grep -qx created=3 "$FIX/o"'
check "token never on the command line" '! grep -q test-token "$FIX/calls.log"'
kev_issue=$(grep -l '"CVE-2099-0004"' "$FIX"/created-*.json)
check "KEV issue: Bug, Highest, due in 3 days, kev label" 'jq -e ".fields.issuetype.name == \"Bug\" and .fields.priority.name == \"Highest\" and .fields.duedate == \"2026-11-19\" and (.fields.labels | index(\"kev\"))" "$kev_issue" >/dev/null'
crit_issue=$(grep -l '"CVE-2099-0001"' "$FIX"/created-*.json)
check "CRITICAL issue: High, due in 7 days" 'jq -e ".fields.priority.name == \"High\" and .fields.duedate == \"2026-11-23\"" "$crit_issue" >/dev/null'
eol_issue=$(grep -l 'lifecycle-eol-spring-boot-3.2' "$FIX"/created-*.json)
check "EOL issue: Task, plan within 30 days" 'jq -e ".fields.issuetype.name == \"Task\" and .fields.duedate == \"2026-12-16\"" "$eol_issue" >/dev/null'
check "descriptions say Jira only, never GitHub Issues" 'jq -r .fields.description "$crit_issue" | grep -q "Do not copy this issue to GitHub Issues"'

out=$(env "${env_common[@]}" "${jira_env[@]}" GITHUB_OUTPUT="$FIX/o2" bash "$s/cve-triage.sh" 2>"$FIX/err")
check "second run of the same repo changes nothing" 'grep -qx created=0 "$FIX/o2" && grep -qx updated=0 "$FIX/o2" && [ "$(ls "$FIX"/comment-* 2>/dev/null | wc -l | tr -d " ")" = 0 ]'

out=$(env "${env_common[@]}" "${jira_env[@]}" REPO=lovablegarden/lovablegarden-other GITHUB_OUTPUT="$FIX/o3" bash "$s/cve-triage.sh" 2>"$FIX/err")
check "another repo updates the same issues (label + one comment each)" 'grep -qx created=0 "$FIX/o3" && grep -qx updated=3 "$FIX/o3" && [ "$(ls "$FIX"/comment-* | wc -l | tr -d " ")" = 3 ]'
check "repo label added" 'grep -q repo-lovablegarden-other "$FIX"/state/secfinding-*.json'

f=$(ls "$FIX"/state/lifecycle-eol-*.json); jq '.fields.status.statusCategory.key = "done"' "$f" > "$f.t" && mv "$f.t" "$f"
out=$(env "${env_common[@]}" "${jira_env[@]}" GITHUB_OUTPUT="$FIX/o4" bash "$s/cve-triage.sh" 2>"$FIX/err")
check "closed issue found again: labelled security-recurred once" 'grep -qx updated=1 "$FIX/o4" && jq -e ".fields.labels | index(\"security-recurred\")" "$f" >/dev/null'
out=$(env "${env_common[@]}" "${jira_env[@]}" GITHUB_OUTPUT="$FIX/o5" bash "$s/cve-triage.sh" 2>"$FIX/err")
check "and not again on the next run" 'grep -qx updated=0 "$FIX/o5"'

touch "$FIX/jira.down"
out=$(env "${env_common[@]}" "${jira_env[@]}" GITHUB_OUTPUT="$FIX/o6" bash "$s/cve-triage.sh" 2>"$FIX/err"); rc=$?
check "Jira down: run fails and says so" '[ $rc = 1 ] && grep -qx failed=3 "$FIX/o6"'

exit $fail
