# security-scan tests (LG-1218, LG-1216, LG-1224)

`test-security-scan.yml` calls the reusable `security-scan.yml` three times and checks its outputs:

| Job | Target | Expected |
| --- | --- | --- |
| `clean` | this repo (fixtures excluded by `.gitleaks.toml` and `trivy.yaml`) | 0 secrets, 0 gating dependency findings, 0 unpinned Actions |
| `vulnerable` | `fixtures/vulnerable`, `enforce: false`, triage dry run | at least 1 secret, 1 fixable CRITICAL dependency (its `.trivyignore` entry expired in 2020), 1 fixable CRITICAL image finding, and at least 1 finding the Jira triage would file |
| `accepted` | `fixtures/accepted` | the same minimist finding hidden by `CVE-2021-44906 exp:2099-12-31`, listed as 1 active acceptance |

The `scripts` job runs `tests/security-tools/run-tests.sh`: the risk-acceptance, lifecycle and Jira triage scripts against fixtures, with `curl` stubbed as Jira and endoflife.date.

Fixtures are inert:

- `fixtures/*/package-lock.json` pins `minimist@1.2.5` (CVE-2021-44906, CRITICAL, fixed in 1.2.6). Nothing installs it.
- `fixtures/vulnerable/app.properties` holds a random string shaped like an API key. It is not a credential for anything.
- The image job scans `mirror.gcr.io/library/alpine:3.12.0`, an old public image with fixable CRITICAL CVEs.
- `tests/security-tools/fixtures` holds made-up `CVE-2099-*` findings and a fake Jira token.
