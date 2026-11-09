# Staff password callables (recovered from prod)

Recovered from prod `practice-firebase-72df1` via sanitized source archive (2026-11-09). Codebase: `tashil-mobile-notifications`, Node.js 22, gen1, `us-central1`.

## Exports (`functions/src/index.ts`)

- `sendStaffPasswordSetupEmail` — admin-only; queues branded setup/forgot mail via `mail` collection
- `requestStaffPasswordReset` — public; phone lookup, anti-enumeration `{ ok: true }`
- `completeStaffPasswordSetup` — public; token + password or token check

## Source modules

- `staff_password_email.ts` — callables
- `password_setup_token_logic.ts` — 7-day hashed setup tokens (`password_setup_tokens`)
- `password_email_template.ts` — RTL HTML/text templates

## Optional environment variables (names only)

| Name | Purpose |
|------|---------|
| `PASSWORD_EMAIL_LOGO_URL` | Hosted logo PNG in email HTML |
| `PASSWORD_ACTION_PAGE_URL` | Custom handler page URL for setup links (default in code: `DEFAULT_ACTION_PAGE_URL`) |

Firebase-injected names also referenced in prod metadata: `FIREBASE_CONFIG`, `GCLOUD_PROJECT`, `EVENTARC_CLOUD_EVENT_SOURCE`.

## Targeted deploy (never blanket functions deploy on shared project)

```bash
firebase deploy --only functions:tashil-mobile-notifications:sendStaffPasswordSetupEmail,functions:tashil-mobile-notifications:requestStaffPasswordReset,functions:tashil-mobile-notifications:completeStaffPasswordSetup --project <project>
```
