#!/usr/bin/env bash
# The java-25-gradle-*.yml templates are generated from their java-21 siblings:
# same file, a "generated" header, and only the JDK version changed.
#
#   tests/java-template-parity/check.sh           # fail if java-25 has drifted
#   tests/java-template-parity/check.sh --write   # regenerate java-25 from java-21
#
# Edit the java-21 template, then run with --write.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOWS="$HERE/../../.github/workflows"
WRITE=false
[ "${1:-}" = "--write" ] && WRITE=true

generate() {
  local kind=$1
  echo "# GENERATED from java-21-gradle-$kind.yml by tests/java-template-parity/check.sh --write."
  echo "# Do not edit directly: change java-21-gradle-$kind.yml and regenerate."
  sed -e 's/Set up JDK 21/Set up JDK 25/' \
      -e "s/java-version: '21'/java-version: '25'/" \
      "$WORKFLOWS/java-21-gradle-$kind.yml"
}

status=0
for kind in ci release; do
  target="$WORKFLOWS/java-25-gradle-$kind.yml"
  if $WRITE; then
    generate "$kind" > "$target"
    echo "wrote java-25-gradle-$kind.yml"
  elif ! diff -u --label "java-25-gradle-$kind.yml" --label "generated from java-21-gradle-$kind.yml" \
      "$target" <(generate "$kind") >&2; then
    echo "java-25-gradle-$kind.yml has drifted from java-21-gradle-$kind.yml (diff above)." >&2
    status=1
  else
    echo "java-25-gradle-$kind.yml matches java-21-gradle-$kind.yml"
  fi
done

if [ "$status" -ne 0 ]; then
  echo "Change the java-21 template, then run: tests/java-template-parity/check.sh --write" >&2
fi
exit "$status"
