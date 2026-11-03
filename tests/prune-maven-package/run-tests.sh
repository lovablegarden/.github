#!/usr/bin/env bash
# Runs the "Prune old Maven versions" step of prune-maven-package.yml against
# fake gh/curl (stubs/) and synthetic fixtures. Needs bash >= 4.4, jq, python3.
#
#   tests/prune-maven-package/run-tests.sh
#
# No network access; nothing real is listed or deleted.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOW="$HERE/../../.github/workflows/prune-maven-package.yml"
BOM=com.lovablegarden.lovablegarden-bom
PLANTS=se.lovablegarden.api.lovablegarden-api-plants
SECURITY=com.lovablegarden.security.lovablegarden-security-common

SCRIPT=$(mktemp)
# The step's run block is the last block in the file, indented 10 spaces
awk '/^        run: \|$/ { on = 1; next } on { print substr($0, 11) }' "$WORKFLOW" > "$SCRIPT"
grep -q 'Reference guard' "$SCRIPT" || { echo "could not extract run block" >&2; exit 1; }
# Actions would read "${{" in the run block as an expression and reject the workflow
! grep -qF '${{' "$SCRIPT" || { echo 'run block contains "${{"' >&2; exit 1; }

export FAKE_APP_TOKEN=app-token FAKE_PACKAGES_TOKEN=packages-pat
PASS=0 FAILED=0
ID=0

# versions <package> <name>@<created_at>... -> fixture listing
versions() {
  local pkg=$1 json='[]' entry
  shift
  for entry in "$@"; do
    ID=$((ID + 1))
    json=$(echo "$json" | jq -c --arg n "${entry%@*}" --arg d "${entry##*@}" --argjson id "$ID" \
      '. + [{id: $id, name: $n, created_at: $d}]')
  done
  echo "$json" > "$FIX/versions/$pkg.json"
}

# pom <bom version> <groupId:artifactId:version>... -> BOM POM fixture
pom() {
  local v=$1 dep g a ver
  shift
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<project xmlns="http://maven.apache.org/POM/4.0.0">'
    echo "  <groupId>com.lovablegarden</groupId><artifactId>lovablegarden-bom</artifactId><version>$v</version>"
    echo '  <dependencyManagement><dependencies>'
    for dep in "$@"; do
      IFS=: read -r g a ver <<< "$dep"
      echo "    <dependency><groupId>$g</groupId><artifactId>$a</artifactId><version>$ver</version></dependency>"
    done
    echo '  </dependencies></dependencyManagement>'
    echo '</project>'
  } > "$FIX/poms/$v.pom"
}

# src <repo> <path> -> writes stdin to a build file in that repo's default branch
src() {
  mkdir -p "$FIX/src/$1/$(dirname "$2")"
  cat > "$FIX/src/$1/$2"
}

# Incident state of 2026-10-25: old BOMs pin api-plants 1.0.0-SNAPSHOT (1.0.3 as a
# timestamped snapshot), consumers still on BOM 1.0.1 and 1.0.4.
baseline() {
  FIX=$(mktemp -d)
  export FIX
  mkdir -p "$FIX/versions" "$FIX/poms" "$FIX/props"
  : > "$FIX/deleted.log"
  : > "$FIX/calls.log"
  PACKAGES_TOKEN=$FAKE_PACKAGES_TOKEN

  versions "$BOM" \
    1.0.5@2026-10-24T18:00:00Z \
    "1.0.3 # x-release-please-version@2026-07-18T16:05:35Z" \
    1.0.4@2026-07-18T16:15:16Z 1.0.3@2026-07-18T16:08:28Z \
    1.0.2@2026-07-07T14:46:23Z 1.0.1@2026-07-01T10:00:00Z
  pom 1.0.1 "com.lovablegarden.security:lovablegarden-security-common:1.0.1" \
    "se.lovablegarden.api:lovablegarden-api-plants:1.0.0-SNAPSHOT"
  pom 1.0.2 "com.lovablegarden.security:lovablegarden-security-common:1.0.2" \
    "se.lovablegarden.api:lovablegarden-api-plants:1.0.0-SNAPSHOT"
  pom 1.0.3 "com.lovablegarden.security:lovablegarden-security-common:1.0.3" \
    "se.lovablegarden.api:lovablegarden-api-plants:1.0.0-20260706.114839-8"
  pom 1.0.4 "com.lovablegarden.security:lovablegarden-security-common:\${project.version}" \
    "se.lovablegarden.api:lovablegarden-api-plants:1.0.0-SNAPSHOT"
  pom 1.0.5 "com.lovablegarden.security:lovablegarden-security-common:1.0.5" \
    "se.lovablegarden.api:lovablegarden-api-plants:4.0.0" \
    "org.springframework.boot:spring-boot-dependencies:3.2.3"

  versions "$PLANTS" \
    4.0.0@2026-10-24T17:46:51Z 3.0.1@2026-10-23T10:56:52Z 3.0.0@2026-10-23T06:53:28Z \
    2.0.0@2026-09-01T00:00:00Z 1.0.0-SNAPSHOT@2026-07-06T11:48:39Z

  versions "$SECURITY" \
    1.1.0-SNAPSHOT@2026-10-26T00:00:00Z 1.0.5@2026-10-24T18:00:00Z 1.0.4@2026-07-18T16:15:16Z \
    1.0.3@2026-07-18T16:08:28Z 1.0.2@2026-07-07T14:46:23Z 1.0.1@2026-07-01T10:00:00Z \
    1.0.0@2026-06-01T00:00:00Z

  jq -n '[
    {name: "lovablegarden-plants", archived: false},
    {name: "lovablegarden-tasks", archived: false},
    {name: "lovablegarden-audit", archived: false},
    {name: "lovablegarden-auth", archived: false},
    {name: "lovablegarden-old", archived: true},
    {name: "other-repo", archived: false}
  ]' > "$FIX/repos.json"
  printf 'version=1.2.3\nlovablegardenBomVersion=1.0.1\n' > "$FIX/props/lovablegarden-plants"
  printf 'lovablegardenBomVersion = 1.0.4\r\n' > "$FIX/props/lovablegarden-tasks"
  printf 'version=0.1.0\n' > "$FIX/props/lovablegarden-audit"
  printf 'lovablegardenBomVersion=1.0.2\n' > "$FIX/props/lovablegarden-old"
  printf 'lovablegardenBomVersion=1.0.2\n' > "$FIX/props/other-repo"
  # Today's form: the client version comes from the BOM
  src lovablegarden-tasks build.gradle <<'GRADLE'
repositories {
    maven { url = uri("https://maven.pkg.github.com/lovablegarden/lovablegarden-api-plants") }
}
dependencies {
    implementation platform("com.lovablegarden:lovablegarden-bom:${lovablegardenBomVersion}")
    implementation 'se.lovablegarden.api:lovablegarden-api-plants'
}
GRADLE
}

# run <package> [dry_run] -> sets OUT and RC
run() {
  set +e
  OUT=$(PATH="$HERE/stubs:$PATH" GH_TOKEN=$FAKE_APP_TOKEN PACKAGES_TOKEN=$PACKAGES_TOKEN \
    PACKAGE_NAME=$1 KEEP_COUNT=3 \
    DRY_RUN=${2:-false} PROTECT_VERSIONS=${3:-} bash "$SCRIPT" 2>&1)
  RC=$?
  set -e
}

check() {
  local desc=$1
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAILED=$((FAILED + 1))
    echo "FAIL: $CASE: $desc"
    echo "$OUT" | sed 's/^/    | /'
  fi
}
has() { tr "\t" " " <<< "$OUT" | grep -qxF -- "$1"; }
keeps() { grep -qE "^KEEP  $1 \(" <<< "$OUT"; }
deletes() { grep -qE "^DELETE $1 \(" <<< "$OUT"; }
deleted_ids() { [ "$(sort -n "$FIX/deleted.log" | paste -sd, -)" = "$1" ]; }
id_of() { jq -r --arg n "$2" '.[] | select(.name == $n) | .id' "$FIX/versions/$1.json"; }
rc() { [ "$RC" = "$1" ]; }

CASE='client: BOM-pinned SNAPSHOT is kept'
baseline
run "$PLANTS"
check 'exit 0' rc 0
for v in 4.0.0 3.0.1 3.0.0 1.0.0-SNAPSHOT; do check "KEEP $v" keeps "$v"; done
check 'DELETE 2.0.0' deletes 2.0.0
check 'only 2.0.0 deleted' deleted_ids "$(id_of "$PLANTS" 2.0.0)"
check 'timestamped snapshot mapped' has "  1.0.0-SNAPSHOT pinned by BOM 1.0.3"

CASE='client: dry run deletes nothing'
baseline
run "$PLANTS" true
check 'exit 0' rc 0
check 'DELETE 2.0.0 listed' deletes 2.0.0
check 'nothing deleted' deleted_ids ''

CASE='client: SNAPSHOT does not take a keep slot, unpinned SNAPSHOT goes'
baseline
run "$SECURITY"
check 'exit 0' rc 0
for v in 1.0.5 1.0.4 1.0.3 1.0.2 1.0.1; do check "KEEP $v (BOM-pinned or newest)" keeps "$v"; done
check 'project.version resolved' has "  1.0.4 pinned by BOM 1.0.4"
check 'DELETE 1.1.0-SNAPSHOT' deletes 1.1.0-SNAPSHOT
check 'DELETE 1.0.0' deletes 1.0.0

CASE='client: protect_versions input still honoured'
baseline
run "$SECURITY" false 'v1.0.0, 1.1.0-SNAPSHOT'
check 'exit 0' rc 0
check 'KEEP 1.0.0' keeps 1.0.0
check 'KEEP 1.1.0-SNAPSHOT' keeps 1.1.0-SNAPSHOT
check 'nothing deleted' deleted_ids ''

CASE='bom: versions used by consumers are kept'
baseline
run "$BOM"
check 'exit 0' rc 0
for v in 1.0.5 1.0.4 1.0.3 1.0.1; do check "KEEP $v" keeps "$v"; done
check 'DELETE 1.0.2' deletes 1.0.2
check 'only 1.0.2 deleted' deleted_ids "$(id_of "$BOM" 1.0.2)"
check 'consumer reason logged' has "  1.0.1 used by lovablegarden-plants"
check 'non-semver name untouched' bash -c '! grep -q "x-release-please" <<< "$0"' "$OUT"

CASE='nothing to prune: guard skipped'
baseline
versions "$PLANTS" 4.0.0@2026-10-24T17:46:51Z 3.0.1@2026-10-23T10:56:52Z
run "$PLANTS"
check 'exit 0' rc 0
check 'no POM downloads' bash -c '! grep -q "^curl" "$0"' "$FIX/calls.log"

CASE='fail closed: POM HTTP 500'
baseline
touch "$FIX/poms/1.0.2.500"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: registry unreachable'
baseline
touch "$FIX/poms/1.0.4.unreachable"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: BOM listed but POM 404'
baseline
rm "$FIX/poms/1.0.1.pom"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='parallel BOM prune: POM 404 for a BOM gone on relisting is skipped'
baseline
rm "$FIX/poms/1.0.2.pom"
jq -c 'map(select(.name != "1.0.2"))' "$FIX/versions/$BOM.json" > "$FIX/versions/$BOM.relist.json"
run "$PLANTS"
check 'exit 0' rc 0
check 'KEEP 1.0.0-SNAPSHOT' keeps 1.0.0-SNAPSHOT
check 'skip logged' has 'BOM 1.0.2: deleted since listing, skipped'

CASE='fail closed: POM without dependencyManagement'
baseline
echo '<project xmlns="http://maven.apache.org/POM/4.0.0"><version>1.0.3</version></project>' > "$FIX/poms/1.0.3.pom"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: unresolved property in POM'
baseline
pom 1.0.3 "se.lovablegarden.api:lovablegarden-api-plants:\${plants.version}"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: no BOM versions listed'
baseline
echo '[]' > "$FIX/versions/$BOM.json"
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: consumer gradle.properties HTTP 500'
baseline
touch "$FIX/props/lovablegarden-tasks.fail"
run "$BOM"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: consumer BOM version is not a plain version'
baseline
printf 'lovablegardenBomVersion=${bom}\n' > "$FIX/props/lovablegarden-tasks"
run "$BOM"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: GH_PACKAGES_TOKEN missing'
baseline
PACKAGES_TOKEN=''
run "$PLANTS"
check 'exit 1' rc 1
check 'reason logged' has '::error::GH_PACKAGES_TOKEN secret not provided; cannot verify references'
check 'nothing deleted' deleted_ids ''

CASE='fail closed: registry rejects the token (HTTP 401)'
baseline
PACKAGES_TOKEN=wrong-token
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: consumer repo not readable with GH_PACKAGES_TOKEN'
baseline
touch "$FIX/props/lovablegarden-tasks.noaccess"
run "$BOM"
check 'exit 1' rc 1
check 'reason logged' has '::error::Could not read lovablegarden-tasks with GH_PACKAGES_TOKEN'
check 'nothing deleted' deleted_ids ''

CASE='bom: empty repo is skipped'
baseline
touch "$FIX/props/lovablegarden-auth.empty"
run "$BOM"
check 'exit 0' rc 0
check 'KEEP 1.0.1' keeps 1.0.1
check 'scan count logged' has 'Scanned 3 lovablegarden-* repositories for lovablegardenBomVersion'

CASE='client: no direct pins, only BOM-managed use'
baseline
run "$PLANTS"
check 'exit 0' rc 0
check 'scan count logged' has 'Scanned 4 lovablegarden-* repositories for direct lovablegarden-api-plants pins'
check 'no direct pin protected' bash -c '! grep -q "pinned in" <<< "$0"' "$OUT"

CASE='client: old version pinned directly in build.gradle survives (LG-1378)'
baseline
src lovablegarden-audit build.gradle <<'GRADLE'
dependencies {
    implementation 'se.lovablegarden.api:lovablegarden-api-plants:2.0.0'
}
GRADLE
run "$PLANTS"
check 'exit 0' rc 0
check 'KEEP 2.0.0' keeps 2.0.0
check 'reason logged' has '  2.0.0 pinned in lovablegarden-audit/build.gradle:2'
check 'nothing deleted' deleted_ids ''

CASE='client: direct pin is kept in a dry run too'
baseline
echo "implementation 'se.lovablegarden.api:lovablegarden-api-plants:2.0.0'" | src lovablegarden-audit build.gradle
run "$PLANTS" true
check 'exit 0' rc 0
check 'KEEP 2.0.0' keeps 2.0.0
check 'nothing deleted' deleted_ids ''

CASE='client: version from gradle.properties, def variable and Kotlin val'
baseline
printf 'version=0.1.0\nplantsApi=2.0.0\n' > "$FIX/props/lovablegarden-audit"
echo 'implementation "se.lovablegarden.api:lovablegarden-api-plants:${plantsApi}"' | src lovablegarden-audit build.gradle
src lovablegarden-auth sub/build.gradle.kts <<'GRADLE'
val plantsClient = "3.0.0"
dependencies { implementation("se.lovablegarden.api:lovablegarden-api-plants:$plantsClient") }
GRADLE
run "$PLANTS"
check 'exit 0' rc 0
check 'gradle.properties resolved' has '  2.0.0 pinned in lovablegarden-audit/build.gradle:1'
check 'Kotlin val resolved' has '  3.0.0 pinned in lovablegarden-auth/sub/build.gradle.kts:2'
check 'KEEP 2.0.0' keeps 2.0.0
check 'nothing deleted' deleted_ids ''

CASE='client: version catalog (version.ref and inline)'
baseline
src lovablegarden-audit gradle/libs.versions.toml <<'TOML'
[versions]
plants = "2.0.0"

[libraries]
plants-api = { module = "se.lovablegarden.api:lovablegarden-api-plants", version.ref = "plants" }
TOML
src lovablegarden-auth gradle/libs.versions.toml <<'TOML'
[libraries]
plants-api = { group = "se.lovablegarden.api", name = "lovablegarden-api-plants", version = "3.0.0" }
plants-bom = { module = "se.lovablegarden.api:lovablegarden-api-plants" }
TOML
run "$PLANTS"
check 'exit 0' rc 0
check 'version.ref resolved' has '  2.0.0 pinned in lovablegarden-audit/gradle/libs.versions.toml:5'
check 'inline version read' has '  3.0.0 pinned in lovablegarden-auth/gradle/libs.versions.toml:2'
check 'nothing deleted' deleted_ids ''

CASE='client: pin in a conditional block counts, a commented-out pin does not'
baseline
src lovablegarden-audit build.gradle <<'GRADLE'
if (project.hasProperty('usePublishedOpenApiModels')) {
    implementation(group: 'se.lovablegarden.api', name: 'lovablegarden-api-plants', version: '3.0.0') {
        exclude group: 'org.openapitools'
    }
}
// implementation 'se.lovablegarden.api:lovablegarden-api-plants:2.0.0'
/* implementation 'se.lovablegarden.api:lovablegarden-api-plants:2.0.0' */
GRADLE
run "$PLANTS"
check 'exit 0' rc 0
check 'map notation read' has '  3.0.0 pinned in lovablegarden-audit/build.gradle:2'
check 'DELETE 2.0.0' deletes 2.0.0
check 'only 2.0.0 deleted' deleted_ids "$(id_of "$PLANTS" 2.0.0)"

CASE='client: another client pinned at the same version does not protect it'
baseline
src lovablegarden-audit build.gradle <<'GRADLE'
implementation 'se.lovablegarden.api:lovablegarden-api-media:2.0.0'
implementation 'se.lovablegarden.api:lovablegarden-api-plants-extra:2.0.0'
GRADLE
run "$PLANTS"
check 'exit 0' rc 0
check 'DELETE 2.0.0' deletes 2.0.0

CASE='fail closed: direct pin version cannot be resolved'
baseline
echo 'implementation "se.lovablegarden.api:lovablegarden-api-plants:${somewhereElse}"' | src lovablegarden-audit build.gradle
run "$PLANTS"
check 'exit 1' rc 1
check 'reason logged' has '::error::lovablegarden-audit/build.gradle:1: cannot resolve ${somewhereElse} in '"'"'${somewhereElse}'"'"
check 'nothing deleted' deleted_ids ''

CASE='fail closed: direct pin built by string concatenation'
baseline
echo "implementation 'se.lovablegarden.api:lovablegarden-api-plants:' + v" | src lovablegarden-audit build.gradle
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: dynamic version range'
baseline
echo "implementation 'se.lovablegarden.api:lovablegarden-api-plants:[2.0,4.0)'" | src lovablegarden-audit build.gradle
run "$PLANTS"
check 'exit 1' rc 1
check 'nothing deleted' deleted_ids ''

CASE='fail closed: repo file tree truncated'
baseline
touch "$FIX/src/lovablegarden-tasks.truncated"
run "$PLANTS"
check 'exit 1' rc 1
check 'reason logged' has '::error::lovablegarden-tasks: file tree too large to list'
check 'nothing deleted' deleted_ids ''

CASE='fail closed: client prune cannot read a repo with GH_PACKAGES_TOKEN'
baseline
touch "$FIX/props/lovablegarden-audit.noaccess"
run "$PLANTS"
check 'exit 1' rc 1
check 'reason logged' has '::error::Could not read lovablegarden-audit with GH_PACKAGES_TOKEN'
check 'nothing deleted' deleted_ids ''

CASE='client: empty repo is skipped'
baseline
touch "$FIX/props/lovablegarden-auth.empty"
run "$PLANTS"
check 'exit 0' rc 0
check 'scan count logged' has 'Scanned 3 lovablegarden-* repositories for direct lovablegarden-api-plants pins'

CASE='non-client package: no build file scan'
baseline
run "$SECURITY"
check 'exit 0' rc 0
check 'no tree listing' bash -c '! grep -q "git/trees" "$0"' "$FIX/calls.log"

echo "${PASS} passed, ${FAILED} failed"
[ "$FAILED" -eq 0 ]
