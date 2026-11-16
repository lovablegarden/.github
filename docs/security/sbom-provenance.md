# SBOMs and release provenance (LG-1220)

Every deployable release carries a machine-readable SBOM and a provenance record that ties it to its source commit, its workflow run and its immutable image digest. The reusable workflow is [`release-provenance.yml`](../../.github/workflows/release-provenance.yml). How to add it to a repo: [adopting](adopting.md#2-release-provenance).

## What each release gets

| Evidence | Where | Kept |
| --- | --- | --- |
| `sbom-<repo>-<version>.cdx.json`: CycloneDX SBOM of the **final image** by digest (OS packages and bundled jars), from Trivy. Without an image (frontend, libraries): the source tree at the tag. | GitHub Release assets; run artifact `release-provenance-<repo>-<version>` | With the release (indefinitely); artifact 90 days |
| `provenance-<repo>-<version>.json`: repo, tag, commit, image repository + digest + platform, Dockerfile base images, workflow and run, SBOM hash and status, final-image scan result, accepted risks, exception | Same | Same |
| GitHub artifact attestation: SLSA build provenance for the image digest, signed by the release workflow's identity | GitHub attestations API, and pushed to GHCR next to the image | As long as the image |
| GitHub artifact attestation: the SBOM, bound to the image digest | Same | Same |

The org is on GitHub Enterprise Cloud, so attestations on private repos are signed by GitHub's private Sigstore instance and never reach the public transparency log.

BuildKit's own provenance on the image stays at `mode=min`: max mode would record build-arg values, and the release build passes a package token as a build arg.

## Gate: what makes a release production-eligible

`release-provenance.yml` fails, after uploading whatever evidence it has, when:

- the SBOM couldn't be generated, or a container SBOM has no operating-system component, or
- the final image has fixable findings at or above `severity-threshold` (default CRITICAL) that the repo's `.trivyignore` doesn't accept ([risk acceptance](cve-policy.md#risk-acceptance)).

The caller runs the system-lock bump only after this job (`needs: [publish-docker, provenance]`), so a failed run keeps the release out of `lovablegarden-system` and away from stage and prod.

**Exception:** re-run the release workflow by hand with the `provenance-exception` input set to the Jira key that records the approved exception. The failures become warnings, and the key is written into `provenance.json` (`"exception": "LG-…"`), so the release stays traceable as an exception.

## provenance.json (v1)

```json
{
  "schema": "https://github.com/lovablegarden/.github/blob/main/docs/security/sbom-provenance.md#provenancejson-v1",
  "repository": "lovablegarden/lovablegarden-tasks",
  "release_tag": "lovablegarden-tasks-v1.1.30",
  "version": "1.1.30",
  "commit": "<40-hex commit of the tag>",
  "image": {"repository": "ghcr.io/lovablegarden/lovablegarden-tasks", "digest": "sha256:…",
            "reference": "ghcr.io/lovablegarden/lovablegarden-tasks@sha256:…", "platform": "linux/arm64"},
  "base_images": ["eclipse-temurin:21-jre-alpine"],
  "build": {"workflow": "lovablegarden/lovablegarden-tasks/.github/workflows/release-published.yml@refs/tags/…",
            "run": "https://github.com/…/actions/runs/…/attempts/1", "event": "release", "actor": "…"},
  "sbom": {"file": "sbom-lovablegarden-tasks-1.1.30.cdx.json", "format": "CycloneDX", "generator": "trivy 0.76.1",
           "status": "success", "sha256": "…", "components": 312},
  "scan": {"tool": "trivy 0.76.1", "db_updated": "…", "status": "success", "threshold": "CRITICAL",
           "fixable_at_or_above_threshold": 0, "accepted_risks": ["CVE-2099-0001"]},
  "exception": null,
  "dry_run": false,
  "generated_at": "2026-11-16T12:00:00Z"
}
```

## Answering questions during an incident

Set the repo and version first:

```bash
repo=lovablegarden/lovablegarden-tasks; v=1.1.30; tag=lovablegarden-tasks-v$v
gh release download "$tag" -R "$repo" -p 'sbom-*.cdx.json' -p 'provenance-*.json' -D /tmp/evidence-$v
```

**Does release X contain dependency Y?**

```bash
jq -r '.components[] | select(.name | test("tomcat-embed-core")) | "\(.group // "")/\(.name) \(.version)"' /tmp/evidence-$v/sbom-*.cdx.json
```

**Is release X affected by CVE Z?** Scan the stored SBOM with today's vulnerability database. This works for old releases too, without pulling the image:

```bash
trivy sbom --format table /tmp/evidence-$v/sbom-*.cdx.json | grep -E 'CVE-2099-0001|Total'
```

Then check `provenance-*.json` → `scan.accepted_risks` and the repo's `.trivyignore` at the tag to see whether it was a known, accepted risk.

**Which releases of every service contain dependency Y?** Loop over the releases:

```bash
for tag in $(gh release list -R "$repo" -L 20 --json tagName --jq '.[].tagName'); do
  gh release download "$tag" -R "$repo" -p 'sbom-*.cdx.json' -O - 2>/dev/null \
    | jq -r --arg t "$tag" '.components[]? | select(.name == "spring-webmvc") | "\($t) \(.version)"'
done
```

Releases from before this workflow was adopted have no SBOM. For those, generate one from the image (`trivy image --format cyclonedx ghcr.io/lovablegarden/<repo>:<version>`), which still works while the image is retained.

**Is this image what we released?** Verify the signed attestation:

```bash
gh attestation verify oci://ghcr.io/lovablegarden/lovablegarden-tasks:1.1.30 --owner lovablegarden
gh attestation verify oci://ghcr.io/lovablegarden/lovablegarden-tasks:1.1.30 --owner lovablegarden \
  --predicate-type https://cyclonedx.org/bom
```

## Reconciling deployed images with the lock and the releases

`lovablegarden-system` locks service versions as tags (`versions/services.lock*.yml`). A tag can be moved; a digest can't. To check that what runs is what was released:

1. From the lock, take `<service>: <version>`.
2. Expected digest: `provenance-<service>-<version>.json` → `image.digest` (or `gh attestation verify` above, which prints it).
3. Registry today: `docker buildx imagetools inspect ghcr.io/lovablegarden/<service>:<version> --format '{{json .Manifest}}' | jq -r .digest`.
4. Running on a host (read-only): `docker inspect --format '{{index .RepoDigests 0}}' <container>`.

All three must agree. A mismatch means the tag moved after the release (the retention or a manual push), or the host runs something else: stop and investigate before the next deploy.

## Retention

- GitHub Release assets stay as long as the release. Releases are never deleted.
- Attestations stay with the image in GHCR and in the attestations API. The GHCR retention policy ([package retention](../../.github/workflows/package-retention-scheduled.yml)) protects versions that a system lock references; an image that is pruned keeps its release assets, so the SBOM survives the image.
- Run artifacts: 90 days.
