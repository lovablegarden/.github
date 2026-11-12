# security-scan tests (LG-1218)

`test-security-scan.yml` calls the reusable `security-scan.yml` twice and checks its outputs:

| Job | Target | Expected |
| --- | --- | --- |
| `clean` | this repo (fixtures excluded by `.gitleaks.toml` and `trivy.yaml`) | 0 secrets, 0 gating dependency findings |
| `vulnerable` | `fixtures/vulnerable`, `enforce: false` | at least 1 secret, 1 fixable CRITICAL dependency, 1 fixable CRITICAL image finding |

Fixtures are inert:

- `fixtures/vulnerable/package-lock.json` pins `minimist@1.2.5` (CVE-2021-44906, CRITICAL, fixed in 1.2.6). Nothing installs it.
- `fixtures/vulnerable/app.properties` holds a random string shaped like an API key. It is not a credential for anything.
- The image job scans `mirror.gcr.io/library/alpine:3.12.0`, an old public image with fixable CRITICAL CVEs.
