#!/usr/bin/env bash
# Lifecycle checks for one repo (LG-1224, docs/security/lifecycle.md).
#
# Usage: lifecycle.sh <repo-root> [image-trivy.json]
#   repo mode  (no second argument): GitHub Actions pinning, Dockerfile base-image pinning, and
#              end-of-life dates for Spring Boot (from gradle.lockfile) and the Java/Node base
#              image versions (from Dockerfile FROM lines).
#   image mode (Trivy JSON of the final image): end-of-life date of the image's OS.
#
# End-of-life dates come from https://endoflife.date (ENDOFLIFE_API, overridable for tests).
# A finding whose ID (EOL-<product>-<cycle> or PIN-...) is listed in <repo-root>/.trivyignore
# with an unexpired `exp:` date is shown as accepted and not counted.
#
# Writes Markdown to stdout, findings as JSON to $LIFECYCLE_JSON (default ./lifecycle.json),
# annotations to stderr, and `findings` / `eol` / `unpinned` counts to $GITHUB_OUTPUT.
# Always exits 0 unless STRICT=true and something is EOL or unpinned.
set -euo pipefail

root="${1:?usage: lifecycle.sh <repo-root> [image-trivy.json]}"
image_json="${2:-}"
api="${ENDOFLIFE_API:-https://endoflife.date/api}"
warn_days="${EOL_WARN_DAYS:-120}"
today="${TODAY:-$(date -u +%F)}"
out_json="${LIFECYCLE_JSON:-lifecycle.json}"
strict="${STRICT:-false}"

to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f %F "$1" +%s; }
now=$(to_epoch "$today")
items="[]"
add() { items=$(jq -c --argjson i "$1" '. + [$i]' <<<"$items"); }

# IDs accepted in .trivyignore with an unexpired exp: date.
accepted() {
  local f="$root/.trivyignore" id="$1"
  [ -f "$f" ] || return 1
  awk -v id="$id" -v today="$today" '
    $1 == id { for (i = 2; i <= NF; i++) if ($i ~ /^exp:/) { e = substr($i, 5); if (e > today) found = 1 } }
    END { exit found ? 0 : 1 }' "$f"
}

# eol <product> <cycle> <source>: look the cycle up on endoflife.date and record it.
eol() {
  local product="$1" cycle="$2" source="$3" body date status left id
  id="EOL-${product}-${cycle}"
  if ! body=$(curl -fsSL --max-time 20 "${api}/${product}/${cycle}.json" 2>/dev/null); then
    echo "::warning::endoflife.date has no data for ${product} ${cycle} (${source}); not checked" >&2
    add "$(jq -nc --arg id "$id" --arg p "$product" --arg c "$cycle" --arg s "$source" \
      '{kind:"eol", id:$id, product:$p, cycle:$c, source:$s, eol:null, status:"unknown"}')"
    return 0
  fi
  date=$(jq -r '.eol | if type == "string" then . elif . == true then "past" else "" end' <<<"$body")
  status="supported"
  if [ "$date" = "past" ]; then
    status="eol"
  elif [ -n "$date" ]; then
    left=$(( ($(to_epoch "$date") - now) / 86400 ))
    if [ "$left" -le 0 ]; then status="eol"; elif [ "$left" -le "$warn_days" ]; then status="eol-soon"; fi
  fi
  if [ "$status" != "supported" ] && accepted "$id"; then status="accepted"; fi
  add "$(jq -nc --arg id "$id" --arg p "$product" --arg c "$cycle" --arg s "$source" --arg d "$date" --arg st "$status" \
    '{kind:"eol", id:$id, product:$p, cycle:$c, source:$s, eol:(if $d == "" then null else $d end), status:$st}')"
  case "$status" in
    eol) echo "::warning::${product} ${cycle} is end-of-life (${date}), used by ${source}. Plan the upgrade (docs/security/lifecycle.md)." >&2 ;;
    eol-soon) echo "::warning::${product} ${cycle} reaches end-of-life on ${date}, used by ${source}." >&2 ;;
  esac
}

if [ -z "$image_json" ]; then
  # 1. GitHub Actions: third-party actions pinned to a full commit SHA. Local actions, docker://
  #    and the org reusables (lovablegarden/.github/...@main, by policy) are exempt.
  if [ -d "$root/.github/workflows" ]; then
    while IFS=: read -r file line ref; do
      ref=$(sed -E "s/^[[:space:]-]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[\"']//g; s/[[:space:]]+$//" <<<"$ref")
      case "$ref" in ./*|docker://*|lovablegarden/.github/*) continue ;; esac
      pinned=$(grep -qE '@[0-9a-f]{40}$' <<<"$ref" && echo true || echo false)
      [ "$pinned" = true ] && continue
      id="PIN-action-${ref%@*}"
      st="unpinned"; accepted "$id" && st="accepted"
      add "$(jq -nc --arg id "$id" --arg r "$ref" --arg f "${file#"$root"/}:$line" --arg st "$st" \
        '{kind:"pin", id:$id, ref:$r, source:$f, status:$st}')"
      [ "$st" = unpinned ] && echo "::warning file=${file#"$root"/},line=${line}::Action ${ref} is not pinned to a commit SHA (docs/security/lifecycle.md)" >&2
    done < <(grep -nHE '^[[:space:]-]*uses:' "$root"/.github/workflows/*.y*ml 2>/dev/null || true)
  fi

  # 2. Dockerfile base images: pinned by digest, plus Java/Node end-of-life.
  while IFS= read -r df; do
    stages=""
    while read -r kw from rest; do
      [ "$(tr '[:lower:]' '[:upper:]' <<<"$kw")" = FROM ] || continue
      case "$from" in --platform=*) from=$(awk '{print $1}' <<<"$rest"); rest=$(cut -d' ' -f2- <<<"$rest");; esac
      alias=$(awk 'toupper($1) == "AS" {print $2}' <<<"$rest")
      if [ "$from" = scratch ] || grep -qxF "$from" <<<"$stages" || grep -q '\$' <<<"$from"; then
        [ -n "$alias" ] && stages="$stages"$'\n'"$alias"
        continue
      fi
      [ -n "$alias" ] && stages="$stages"$'\n'"$alias"
      src="${df#"$root"/}"
      if ! grep -q '@sha256:' <<<"$from"; then
        id="PIN-image-${from%%:*}"
        st="unpinned"; accepted "$id" && st="accepted"
        add "$(jq -nc --arg id "$id" --arg r "$from" --arg f "$src" --arg st "$st" '{kind:"pin", id:$id, ref:$r, source:$f, status:$st}')"
        [ "$st" = unpinned ] && echo "::warning file=${src}::Base image ${from} is not pinned by digest (docs/security/lifecycle.md)" >&2
      fi
      name="${from%%@*}"; tag="${name#*:}"; [ "$tag" = "$name" ] && tag=""; name="${name%%:*}"; name="${name##*/}"
      major=$(grep -oE '^[0-9]+' <<<"$tag" || true)
      [ -n "$major" ] || continue
      case "$name" in
        eclipse-temurin|temurin) eol eclipse-temurin "$major" "$src" ;;
        node) eol nodejs "$major" "$src" ;;
      esac
    done < "$df"
  done < <(find "$root" -maxdepth 3 -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) -not -path '*/node_modules/*' 2>/dev/null)

  # 3. Spring Boot from the resolved runtime classpath (gradle.lockfile written by the scan).
  boot=$(find "$root" -name gradle.lockfile -not -path '*/.gradle/*' -exec grep -hoE '^org\.springframework\.boot:spring-boot:[0-9]+\.[0-9]+' {} + 2>/dev/null \
    | sed 's/.*://' | sort -uV | head -1 || true)
  [ -n "$boot" ] && eol spring-boot "$boot" "runtimeClasspath"
else
  # Image mode: the final image's OS, from Trivy's metadata.
  family=$(jq -r '.Metadata.OS.Family // empty' "$image_json")
  version=$(jq -r '.Metadata.OS.Name // empty' "$image_json")
  image=$(jq -r '.ArtifactName // "image"' "$image_json")
  trivy_eosl=$(jq -r '.Metadata.OS.EOSL // false' "$image_json")
  case "$family" in
    alpine) eol alpine "$(cut -d. -f1-2 <<<"$version")" "$image" ;;
    debian) eol debian "$(cut -d. -f1 <<<"$version")" "$image" ;;
    ubuntu) eol ubuntu "$(cut -d. -f1-2 <<<"$version")" "$image" ;;
    "") ;;
    *) [ "$trivy_eosl" = true ] && echo "::warning::${image}: ${family} ${version} is end-of-life according to Trivy" >&2 ;;
  esac
fi

items=$(jq -c 'unique_by(.kind + "|" + .id + "|" + (.ref // ""))' <<<"$items")
jq '.' <<<"$items" > "$out_json"
eolc=$(jq '[.[] | select(.kind == "eol" and (.status == "eol" or .status == "eol-soon"))] | length' <<<"$items")
unp=$(jq '[.[] | select(.status == "unpinned")] | length' <<<"$items")

if [ -z "$image_json" ]; then echo "### Lifecycle (LG-1224)"; else echo "### Lifecycle: image OS"; fi
if [ "$items" = "[]" ]; then
  echo "Nothing to check."
else
  echo "**${eolc}** component(s) end-of-life or within ${warn_days} days of it, **${unp}** unpinned reference(s). Report only."
  echo
  echo "| Check | Component | Source | End of life | Status |"
  echo "| --- | --- | --- | --- | --- |"
  jq -r '.[] | if .kind == "eol"
      then "| EOL | \(.product) \(.cycle) | \(.source) | \(.eol // "-") | \(.status) |"
      else "| Pin | `\(.ref)` | \(.source) | - | \(.status) |" end' <<<"$items" | sort -u
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "eol=$eolc"; echo "unpinned=$unp"; echo "findings=$((eolc + unp))"; } >> "$GITHUB_OUTPUT"
fi
if [ "$strict" = true ] && [ $((eolc + unp)) -gt 0 ]; then exit 1; fi
exit 0
