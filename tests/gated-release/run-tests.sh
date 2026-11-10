#!/usr/bin/env bash
# Tests for scripts/release/checks-green.sh and scripts/release/merge-bot-pr.sh against a stub `gh`.
# Run: tests/gated-release/run-tests.sh   (needs bash and jq; no network, no GitHub token)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# Stub gh: answers from fixture files in $FIX and logs every call to $FIX/calls.
# $FIX/newer: one main commit per line, `sha|message|file,file` (\n in message = newline).
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$FIX/calls"
case "$*" in
  api\ repos/*/compare/*)
    [ -f "$FIX/newer" ] && cut -d'|' -f1 "$FIX/newer"; exit 0 ;;
  "api repos/"*"/commits/"*)
    c=${2##*/}; line=$(grep "^${c}|" "$FIX/newer")
    case "$*" in
      *".commit.message"*) printf '%b\n' "$(echo "$line" | cut -d'|' -f2)" ;;
      *) echo "$line" | cut -d'|' -f3 | tr ',' '\n' ;;
    esac; exit 0 ;;
esac
case "$1 $2" in
  "api --paginate")
    jq -r '.check_runs[] | [.name, .status, (.conclusion // "")] | @tsv' "$FIX/check-runs.json" ;;
  "pr list") cat "$FIX/pr-list.json" ;;
  "pr merge") echo merged ;;
  "api -X") [ -f "$FIX/delete-fails" ] && exit 1; exit 0 ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

pass=0; fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1: expected '$2', got '$3'"; fi
}

new_fixture() {
  export FIX="$WORK/fix$RANDOM$RANDOM"; mkdir -p "$FIX"; : > "$FIX/calls"
}
runs() { # runs name:status:conclusion ...
  local items=() n s c
  for r in "$@"; do
    IFS=: read -r n s c <<< "$r"
    items+=("$(jq -n --arg n "$n" --arg s "$s" --arg c "$c" \
      '{name:$n,status:$s,conclusion:(if $c=="" then null else $c end)}')")
  done
  printf '%s\n' "${items[@]}" | jq -s '{check_runs:.}' > "$FIX/check-runs.json"
}
pr() { # pr <author> <title> <sha> <file>...
  local author=$1 title=$2 sha=$3; shift 3
  jq -n --arg a "$author" --arg t "$title" --arg s "$sha" --args \
    '[{number:301,title:$t,author:{login:$a},headRefOid:$s,isDraft:false,
       files:[$ARGS.positional[]|{path:.}]}]' "$@" > "$FIX/pr-list.json"
}
merge_call() { grep '^pr merge' "$FIX/calls" || true; }
merges() { merge_call | grep -c . | tr -d ' '; }

CG="$ROOT/scripts/release/checks-green.sh"
MB="$ROOT/scripts/release/merge-bot-pr.sh"
BOT=app/lovablegarden-bot

# ============ Service repo settings (the defaults) ============================================
export REQUIRED_CHECKS=$'ci / Build Application\nmigration-lint'
unset BUMP_FILES RELEASE_FILES COMPONENT_PATHS
GREEN=("ci / Build Application:completed:success" "migration-lint:completed:success")

# --- checks-green.sh ---
new_fixture; runs "${GREEN[@]}" "release / merge:in_progress:" "ci / Publish Docker Image:completed:skipped"
"$CG" o/r abc >/dev/null; check "all required green, others running/skipped -> 0" 0 $?

new_fixture; runs "ci / Build Application:completed:success" "migration-lint:in_progress:"
"$CG" o/r abc >/dev/null; check "one required check running -> 2" 2 $?

new_fixture; runs "ci / Build Application:completed:success"
"$CG" o/r abc >/dev/null; check "required check missing -> 2" 2 $?

new_fixture; runs "ci / Build Application:completed:failure" "migration-lint:in_progress:"
"$CG" o/r abc >/dev/null; check "failed beats pending -> 1" 1 $?

new_fixture; runs "${GREEN[@]}" "publish-jar:completed:failure"
"$CG" o/r abc >/dev/null; check "non-required failure ignored -> 0" 0 $?

new_fixture; runs "ci / Build Application:completed:cancelled" "migration-lint:completed:success"
"$CG" o/r abc >/dev/null; check "cancelled required check -> 1" 1 $?

new_fixture; runs "${GREEN[@]}"
REQUIRED_CHECKS=$'\n  \n' "$CG" o/r abc >/dev/null; check "empty REQUIRED_CHECKS -> 1 (never green by default)" 1 $?

new_fixture; runs "${GREEN[@]}"
REQUIRED_CHECKS=$'  ci / Build Application  \n\n' "$CG" o/r abc >/dev/null; check "whitespace around names trimmed -> 0" 0 $?

# --- merge-bot-pr.sh: BOM bump in a service ---
SR=release-please--branches--main--components--lovablegarden-users
REL=(CHANGELOG.md .github/.release-please-manifest.json gradle.properties)

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore: bump lovablegardenBomVersion to 7.0.1" sha1 gradle.properties
"$MB" o/r bump/bom-7.0.1-lovablegarden-users sha1 >/dev/null; check "green BOM bump -> exit 0" 0 $?
check "BOM bump merges as fix(deps)" \
  "pr merge 301 -R o/r --squash --match-head-commit sha1 --subject fix(deps): bump lovablegardenBomVersion to 7.0.1 (#301) --body Merged by gated-release.yml after the required checks passed on sha1." \
  "$(merge_call)"
check "bump branch deleted" 1 "$(grep -c "^api -X DELETE repos/o/r/git/refs/heads/bump/bom-7.0.1-lovablegarden-users" "$FIX/calls")"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore: bump x" sha1 gradle.properties build.gradle
"$MB" o/r bump/x sha1 >/dev/null 2>&1; check "service bump touching build.gradle -> exit 1" 1 $?
check "service bump touching build.gradle -> no merge" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore: bump x" sha1 versions/services.lock.yml
"$MB" o/r bump/x sha1 >/dev/null 2>&1; check "service rejects a lock-file bump by default -> exit 1" 1 $?

# --- merge-bot-pr.sh: service release PR ---
new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
"$MB" o/r "$SR" sha1 >/dev/null; check "green service release PR -> exit 0" 0 $?
check "release PR keeps its chore(main) title" 1 "$(merge_call | grep -c -- '--subject chore(main): release lovablegarden-users 1.0.2 (#301)')"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 CHANGELOG.md src/main/App.java
"$MB" o/r "$SR" sha1 >/dev/null 2>&1; check "release PR touching source -> exit 1" 1 $?
check "release PR touching source -> no merge" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
echo "c1|fix(auth): reject expired token (#12)|src/main/Auth.java" > "$FIX/newer"
"$MB" o/r "$SR" sha1 >/dev/null; check "release PR behind a fix on main -> exit 0" 0 $?
check "release PR behind a fix on main -> no merge (race guard)" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
echo "c1|fix(deps): bump lovablegardenBomVersion to 7.0.1 (#13)|gradle.properties" > "$FIX/newer"
"$MB" o/r "$SR" sha1 >/dev/null
check "release PR behind a merged BOM bump -> waits" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
echo 'c1|chore: tidy logging (#14)\n\nRelease-As: 1.0.3|src/main/Log.java' > "$FIX/newer"
"$MB" o/r "$SR" sha1 >/dev/null
check "release PR behind a Release-As footer -> waits" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
echo 'c1|feat!: new users endpoint (#15)|src/main/Api.java' > "$FIX/newer"
"$MB" o/r "$SR" sha1 >/dev/null
check "release PR behind a breaking feat -> waits" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-users 1.0.2" sha1 "${REL[@]}"
printf '%s\n' "c1|docs: readme (#16)|README.md" "c2|ci: adjust (#17)|.github/workflows/ci.yml" \
  "c3|refactor: rename (#18)|src/main/A.java" "c4|test: more (#19)|src/test/T.java" \
  "c5|build: gradle (#20)|build.gradle" "c6|chore: misc (#21)|x" > "$FIX/newer"
"$MB" o/r "$SR" sha1 >/dev/null
check "release PR behind only non-releasable commits -> merges" 1 "$(merges)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore: bump x" sha1 gradle.properties
echo "c1|fix: something (#22)|src/main/A.java" > "$FIX/newer"
"$MB" o/r bump/x sha1 >/dev/null
check "bump PRs ignore newer main commits -> merges" 1 "$(merges)"

# --- merge-bot-pr.sh: generic refusals ---
new_fixture; runs "ci / Build Application:completed:success" "migration-lint:in_progress:"
pr $BOT "chore: bump x" sha1 gradle.properties
"$MB" o/r bump/x sha1 >/dev/null; check "checks pending -> exit 0" 0 $?
check "checks pending -> no merge" "" "$(merge_call)"

new_fixture; runs "ci / Build Application:completed:failure" "migration-lint:completed:success"
pr $BOT "chore: bump x" sha1 gradle.properties
"$MB" o/r bump/x sha1 >/dev/null 2>&1; check "checks failed -> exit 1" 1 $?
check "checks failed -> no merge" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr someone-else "chore: bump x" sha1 gradle.properties
"$MB" o/r bump/x sha1 >/dev/null 2>&1; check "human-authored bump branch -> exit 1" 1 $?
check "human-authored -> no merge" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
pr $BOT "chore: bump x" newer gradle.properties
"$MB" o/r bump/x sha1 >/dev/null; check "stale run (head moved) -> exit 0" 0 $?
check "stale run -> no merge" "" "$(merge_call)"

new_fixture; runs "${GREEN[@]}"
jq '.[0].isDraft=true' <<< '[{"number":301,"title":"chore: bump x","author":{"login":"app/lovablegarden-bot"},"headRefOid":"sha1","isDraft":false,"files":[{"path":"gradle.properties"}]}]' > "$FIX/pr-list.json"
"$MB" o/r bump/x sha1 >/dev/null; check "draft PR -> exit 0" 0 $?
check "draft PR -> no merge" "" "$(merge_call)"

new_fixture; echo '[]' > "$FIX/pr-list.json"
"$MB" o/r bump/x sha1 >/dev/null; check "no open PR -> exit 0" 0 $?

new_fixture
"$MB" o/r feature/something sha1 >/dev/null; check "other branch -> exit 0" 0 $?
check "other branch -> gh never called" "" "$(cat "$FIX/calls")"

new_fixture; runs "${GREEN[@]}"; touch "$FIX/delete-fails"
pr $BOT "chore: bump x" sha1 gradle.properties
"$MB" o/r bump/x sha1 >/dev/null; check "branch delete failure does not fail the merge" 0 $?

# ============ lovablegarden-system settings (two components) ===================================
export REQUIRED_CHECKS=$'Build and Test System Image\nGateway routing (dev)\nGateway routing (stage)\nGateway routing (prod)'
export BUMP_FILES='^versions/services\.lock(\.prod|\.stage)?\.yml$'
export RELEASE_FILES='^(CHANGELOG\.md|\.github/\.release-please-manifest\.json|gradle\.properties|supabase-jwt-validator/(CHANGELOG\.md|package\.json|package-lock\.json))$'
export COMPONENT_PATHS='supabase-jwt-validator=^supabase-jwt-validator/'
SYS_GREEN=("Build and Test System Image:completed:success" "Gateway routing (dev):completed:success"
           "Gateway routing (stage):completed:success" "Gateway routing (prod):completed:success")
R=release-please--branches--main--components--lovablegarden-system
V=release-please--branches--main--components--supabase-jwt-validator
LOCKS=(versions/services.lock.yml versions/services.lock.prod.yml)

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore: bump lovablegarden-gardenbook to lovablegarden-gardenbook-v1.0.26" sha1 "${LOCKS[@]}"
"$MB" o/r bump/lovablegarden-gardenbook-v1.0.26 sha1 >/dev/null
check "system lock bump merges as fix(deps)" 1 "$(merge_call | grep -c -- '--subject fix(deps): bump lovablegarden-gardenbook to lovablegarden-gardenbook-v1.0.26 (#301)')"

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-system 1.0.61" sha1 CHANGELOG.md .github/.release-please-manifest.json
echo "c1|fix(deps): bump lovablegarden-media to lovablegarden-media-v1.0.8 (#231)|versions/services.lock.yml,versions/services.lock.prod.yml" > "$FIX/newer"
"$MB" o/r "$R" sha1 >/dev/null
check "system release PR waits for a lock bump (v1.0.60 race)" "" "$(merge_call)"

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-system 1.0.61" sha1 CHANGELOG.md .github/.release-please-manifest.json
echo "c1|fix: validator header (#234)|supabase-jwt-validator/server.js" > "$FIX/newer"
"$MB" o/r "$R" sha1 >/dev/null
check "system release PR ignores a validator-only fix -> merges" 1 "$(merges)"

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore(main): release supabase-jwt-validator 1.0.51" sha1 \
  .github/.release-please-manifest.json supabase-jwt-validator/CHANGELOG.md supabase-jwt-validator/package.json
echo "c1|fix: validator header (#234)|supabase-jwt-validator/server.js" > "$FIX/newer"
"$MB" o/r "$V" sha1 >/dev/null
check "validator release PR waits for a validator fix" "" "$(merge_call)"

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore(main): release supabase-jwt-validator 1.0.51" sha1 \
  .github/.release-please-manifest.json supabase-jwt-validator/CHANGELOG.md
echo "c1|fix(gateway): route defaults (#235)|scripts/gateway.conf" > "$FIX/newer"
"$MB" o/r "$V" sha1 >/dev/null
check "validator release PR ignores a system-only fix -> merges" 1 "$(merges)"

new_fixture; runs "${SYS_GREEN[@]}"
pr $BOT "chore(main): release lovablegarden-system 1.0.60" sha1 CHANGELOG.md scripts/deploy.sh
"$MB" o/r "$R" sha1 >/dev/null 2>&1; check "system release PR touching a script -> exit 1" 1 $?

echo; echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
