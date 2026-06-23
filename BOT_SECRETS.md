# Required organization secrets for release automation

Configure these under **lovablegarden org → Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `LOVABLEGARDEN_BOT_APP_ID` | GitHub App ID (numeric) |
| `LOVABLEGARDEN_BOT_PRIVATE_KEY` | Full `.pem` private key from the App |

The App must be installed on: `lovablegarden-system`, `lovablegarden-plants`, `lovablegarden-gardendesk`, `lovablegarden-security-common`.

**Repository permissions (App):** Contents Read & write, Pull requests Read & write.

Pilot workflows pass `LOVABLEGARDEN_BOT_APP_ID` and `LOVABLEGARDEN_BOT_PRIVATE_KEY` explicitly into reusable workflows (org secrets must be visible to each pilot repo).

Workflows mint a short-lived installation token via `actions/create-github-app-token` — do not store PATs in `LOVABLEGARDEN_BOT_PAT`.
