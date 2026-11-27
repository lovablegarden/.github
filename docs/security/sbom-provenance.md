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

BuildKit's own provenance on the image stays at `mode=min`; the signed provenance above is the record. No org workflow passes a token as a build-arg (LG-1468): the packages token reaches BuildKit only as a secret (`RUN --mount=type=secret,id=GH_PACKAGE_TOKEN`), which is never written to image history or provenance.

`release-docker-publish.yml` builds the commit of the release tag, also on a manual `workflow_dispatch` (LG-1469), and refuses to push a version tag that already exists in GHCR (LG-1471). Its `tag` output is the git tag it built; pass that to `release-provenance.yml` so both use the same commit.

## Source SBOMs (no image: libraries, specs, frontend)

Without `image`, the SBOM describes the source tree at the release tag:

| Repo type | What the SBOM lists | How |
| --- | --- | --- |
| Gradle (e.g. lovablegarden-security-common) | The resolved `runtimeClasspath` of every project, transitive dependencies included. A BOM/platform project adds nothing (it has constraints, not dependencies). | The workflow locks `runtimeClasspath` into temporary `gradle.lockfile`s (nothing is committed), so no lock file is needed in the repo. JDK from `java-version` (default 21); private packages read with `GH_PACKAGES_TOKEN`. |
| npm / yarn / pnpm with runtime dependencies (frontend) | `dependencies` from the lock file | Trivy reads the lock file. |
| npm with only devDependencies (e.g. lovablegarden-openapi-spec) | The devDependencies: the build tooling that generates and publishes the release | Automatic when there are no runtime dependencies, or always with `include-dev-deps: true`. `provenance.json` then says `"dev_dependencies": true`. |

The API clients that openapi-spec publishes are generated at release time and aren't in its tree. Their runtime dependencies reach production inside the services, so they appear in each service's image SBOM.

If the SBOM is still empty (no lock file, no `runtimeClasspath`), the job fails and says so. A repo that really ships no third-party dependencies releases with an `exception` naming the Jira issue that records that.

## Gate: what makes a release production-eligible

`release-provenance.yml` fails, after uploading whatever evidence it has, when:

- the SBOM couldn't be generated or lists no components, or a container SBOM has no operating-system component, or
- the final image has fixable findings at or above `severity-threshold` (default CRITICAL) that the repo's `.trivyignore` doesn't accept ([risk acceptance](cve-policy.md#risk-acceptance)).

Fixable findings at or above `report-threshold` (default HIGH) that `.trivyignore` doesn't accept are reported, not gated (LG-1562): each run warns with the count and the first 20 rows, lists them in the job summary, and records `report_threshold` and `fixable_at_or_above_report_threshold` in `provenance.json`. Accept a known HIGH with a dated `.trivyignore` line to silence it.

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
           "status": "success", "sha256": "…", "components": 312, "dev_dependencies": false},
  "scan": {"tool": "trivy 0.76.1", "db_updated": "…", "status": "success", "threshold": "CRITICAL",
           "fixable_at_or_above_threshold": 0,
           "report_threshold": "HIGH", "fixable_at_or_above_report_threshold": 0, "accepted_risks": ["CVE-2099-0001"]},
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
sw=lovablegarden/.github/.github/workflows/release-provenance.yml   # the reusable workflow signs
gh attestation verify oci://ghcr.io/lovablegarden/lovablegarden-tasks:1.1.30 \
  --repo lovablegarden/lovablegarden-tasks --signer-workflow "$sw"
gh attestation verify oci://ghcr.io/lovablegarden/lovablegarden-tasks:1.1.30 \
  --repo lovablegarden/lovablegarden-tasks --signer-workflow "$sw" --predicate-type https://cyclonedx.org/bom
```

Without `--signer-workflow` (or `--signer-repo lovablegarden/.github`), `gh` expects the signer to be a workflow in the service repo itself and rejects the attestation (`verifying with issuer "GitHub, Inc."`). `--owner lovablegarden` also passes, but it accepts any signer in the org; use `--repo` with `--signer-workflow`.

`--repo` is the repository that builds the image, which isn't always the image name: the JWT validator is built in `lovablegarden-system`:

```bash
gh attestation verify oci://ghcr.io/lovablegarden/supabase-jwt-validator:1.0.52 \
  --repo lovablegarden/lovablegarden-system --signer-workflow "$sw"
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
- In GHCR an attestation is its own package version, tagged `sha256-<image digest>` (the OCI referrers tag). [`prune-ghcr-package.yml`](../../.github/workflows/prune-ghcr-package.yml) keeps it as long as its image is kept (a kept release, a protected pin, or an untagged image such as a rollback digest), and deletes it together with its image. Before LG-1471 (17 Nov 2026) the prune treated these tags as branch builds and deleted them: the GHCR copy of the `supabase-jwt-validator` 1.0.51 attestation is gone. `gh attestation verify` reads the attestations API, so verification never depended on the GHCR copy.
- Run artifacts: 90 days.
