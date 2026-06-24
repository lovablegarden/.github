# GitHub App credentials for release automation

Configure under **lovablegarden org → Settings**:

## Required

| Kind | Name | Value |
|------|------|--------|
| **Actions variable** (recommended) | `LOVABLEGARDEN_BOT_APP_ID` | Numeric App ID from the GitHub App settings page |
| **Actions secret** | `LOVABLEGARDEN_BOT_PRIVATE_KEY` | Full `.pem` private key (including BEGIN/END lines) |

The App ID is public; a variable is fine. The private key must remain a secret.

Alternatively, store the App ID as org **secret** `LOVABLEGARDEN_BOT_APP_ID` instead of a variable.

## App installation

Install the App on:

- `lovablegarden-system`
- `lovablegarden-plants`
- `lovablegarden-gardendesk`
- `lovablegarden-security-common`
- `lovablegarden-tasks`
- `lovablegarden-audit`

The org installation (`lovablegarden-bot`) is configured for **all repositories**; new service repos are covered automatically once release-please is wired.

**Repository permissions:** Contents Read & write, Pull requests Read & write.

## Pilot workflow wiring

Pass the private key into reusable workflows from `lovablegarden/.github`:

```yaml
secrets:
  LOVABLEGARDEN_BOT_PRIVATE_KEY: ${{ secrets.LOVABLEGARDEN_BOT_PRIVATE_KEY }}
  # Optional if not using org variable for App ID:
  LOVABLEGARDEN_BOT_APP_ID: ${{ secrets.LOVABLEGARDEN_BOT_APP_ID }}
```

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Input required and not supplied: app-id` | Add org **variable** `LOVABLEGARDEN_BOT_APP_ID` or secret with that name |
| `not permitted to create pull requests` | App needs Pull requests write; install App on target repo |
| Cross-repo PR fails | App must be installed on **both** source and target repos |

Do **not** put the private key in `LOVABLEGARDEN_BOT_PAT` — workflows mint short-lived installation tokens automatically.
