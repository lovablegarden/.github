#!/usr/bin/env bash
# Runs the "Prune old GHCR versions" step of prune-ghcr-package.yml against a fake `gh`
# and synthetic package listings. Needs bash, jq, python3. No network; nothing real is deleted.
#
#   tests/prune-ghcr-package/run-tests.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOW="$HERE/../../.github/workflows/prune-ghcr-package.yml"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The prune step's run block is the last block in the file, indented 10 spaces.
awk '/^      - name: Prune old GHCR versions$/ { step = 1 } step && /^        run: \|$/ { on = 1; next } on { print substr($0, 11) }' \
  "$WORKFLOW" > "$WORK/step.sh"
grep -q 'referrer_re' "$WORK/step.sh" || { echo "could not extract the prune step" >&2; exit 1; }
! grep -qF '${{' "$WORK/step.sh" || { echo 'run block contains "${{"' >&2; exit 1; }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh api [-H x] [--method DELETE] <path>
method=GET path=
while [ $# -gt 0 ]; do
  case "$1" in
    api) ;;
    -H) shift ;;
    --method) method=$2; shift ;;
    *) path=$1 ;;
  esac
  shift
done
if [ "$method" = DELETE ]; then echo "${path##*/}" >> "$FIX_DELETED"; exit 0; fi
case "$path" in
  *page=1) cat "$FIX_VERSIONS" ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$WORK/bin/gh"

PASS=0 FAILED=0
D() { printf 'sha256:%064d' "$1"; }          # fake digest from a number
R() { printf 'sha256-%064d' "$1"; }          # referrer tag for that digest
# v <id> <digest-number> <created> <tag,tag|-> -> one version object
v() { jq -nc --argjson id "$1" --arg n "$(D "$2")" --arg c "$3" --arg t "$4" \
  '{id: $id, name: $n, created_at: $c, metadata: {container: {tags: (if $t == "-" then [] else ($t | split(",")) end)}}}'; }

run() { # run <name> <protect> <expected deleted ids, space separated> <version objects...>
  local name=$1 protect=$2 want=$3; shift 3
  printf '%s\n' "$@" | jq -s . > "$WORK/versions.json"
  : > "$WORK/deleted"
  if ! (cd "$WORK" && PATH="$WORK/bin:$PATH" RUNNER_TEMP="$WORK" FIX_VERSIONS="$WORK/versions.json" \
        FIX_DELETED="$WORK/deleted" GH_TOKEN=x IMAGE_NAME=img KEEP_COUNT=2 DRY_RUN=false \
        PROTECT_TAGS="$protect" SOURCE_REPO=img bash "$WORK/step.sh" > "$WORK/out" 2>&1); then
    FAILED=$((FAILED + 1)); echo "FAIL $name: step failed"; cat "$WORK/out"; return
  fi
  got=$(sort -n "$WORK/deleted" | tr '\n' ' ' | sed 's/ $//')
  if [ "$got" = "$want" ]; then PASS=$((PASS + 1)); echo "ok   $name"
  else FAILED=$((FAILED + 1)); echo "FAIL $name: deleted '$got', want '$want'"; cat "$WORK/out"; fi
}

# 1.0.52 (latest) and its attestation; 1.0.51 and its attestation; 1.0.50 old with attestation;
# an untagged original image with an attestation (rollback digest); CI sha- builds; an orphan referrer.
run "keeps attestations of kept versions, deletes those of pruned ones" "latest" "3 4 7 8" \
  "$(v 1 52 2026-11-16T20:38Z 1.0.52,latest)" \
  "$(v 2 152 2026-11-16T20:39Z "$(R 52)")" \
  "$(v 3 50 2026-11-08T10:00Z 1.0.50)" \
  "$(v 4 150 2026-11-08T10:01Z "$(R 50)")" \
  "$(v 5 51 2026-11-16T19:47Z 1.0.51)" \
  "$(v 6 151 2026-11-16T19:49Z "$(R 51)")" \
  "$(v 7 900 2026-11-17T08:47Z sha-abc)" \
  "$(v 8 999 2026-11-10T00:00Z "$(R 4242)")"

run "keeps the attestation of an untagged (rollback) image" "latest" "" \
  "$(v 1 52 2026-11-16T20:38Z 1.0.52,latest)" \
  "$(v 2 20 2026-11-16T19:47Z -)" \
  "$(v 3 120 2026-11-16T19:49Z "$(R 20)")"

run "keeps attestations of a protected (prod lock) version outside keep_count" "latest,1.0.40" "3 4" \
  "$(v 1 52 2026-11-16T20:38Z 1.0.52,latest)" \
  "$(v 2 51 2026-11-15T20:38Z 1.0.51)" \
  "$(v 3 41 2026-11-14T20:38Z 1.0.41)" \
  "$(v 4 141 2026-11-14T20:39Z "$(R 41)")" \
  "$(v 5 40 2026-11-01T20:38Z 1.0.40)" \
  "$(v 6 140 2026-11-01T20:39Z "$(R 40)")"

run "referrer tags with a suffix (.att/.sig) follow their subject" "latest" "3 4" \
  "$(v 1 52 2026-11-16T20:38Z 1.0.52,latest)" \
  "$(v 2 152 2026-11-16T20:39Z "$(R 52).att")" \
  "$(v 3 900 2026-11-17T08:47Z sha-abc)" \
  "$(v 4 1900 2026-11-17T08:48Z "$(R 900).sig")"

run "a referrer tag never makes its own version count as a release" "latest" "" \
  "$(v 1 52 2026-11-16T20:38Z 1.0.52,latest)" \
  "$(v 2 51 2026-11-15T20:38Z 1.0.51)" \
  "$(v 3 151 2026-11-15T20:39Z "$(R 51)")"

echo "prune-ghcr-package: $PASS passed, $FAILED failed"
[ "$FAILED" = 0 ]
