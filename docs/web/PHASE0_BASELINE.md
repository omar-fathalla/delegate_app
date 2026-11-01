# Phase 0 – Firestore/Storage rules baseline (Flutter Web for staff)

Snapshot date: 2026-11-01 (Cairo). Read-only. Nothing deployed.

## Three rule versions
| File | Lines | Status |
|---|---|---|
| `firestore.rules.deployed` | ~653 | **What production runs today** (pulled read-only) |
| `firestore.rules` (this repo) | 1099 | Strict, company-scoped. **Never deployed.** |
| `delegate_web/tashil/firestore.rules` (Angular) | 385 | Older; deploying from Angular folder would overwrite both |
| `storage.rules.deployed` | ~84 | Production Storage rules: mostly `allow read, write: if isAuthenticated()` |

## Key differences / الفروق المهمة
- Deployed: `/{path=**}/delegates/{id}` → `allow read, write: if request.auth != null` (anonymous included). Any signed-in user can read/write every delegate in every company.
- Deployed: `/{path=**}/companies/{id}` → `allow read: if true` (public), `write: if isAuthenticated()`.
- Local strict rules: scope by `users/{uid}.organizationUID/companyUID`, role lists, device-binding guards, OTP claims.
- Local strict rules do **not** list `company_supervisor`/`supervisor` in `canReadDelegate`/`canReadNestedDelegate`. In data, supervisors are stored as `company-admin` (413 docs), so most are covered; the single `company_supervisor` doc would be locked out.
- Roles without `companyUID` that local rules treat as company-scoped (branches_marketing 9, accountant 1, 6 company-admin) would lose access if local rules were deployed as-is.

## Security gaps (to fix additively in Phase 1)
1. Anonymous/any auth user can write delegates (incl. device binding fields).
2. Companies readable without auth.
3. Storage: any signed-in user reads/writes all paths.
4. Two divergent rule sources (app vs Angular) → risk of accidental overwrite.

## Rule for Phase 1
Start from `firestore.rules.deployed`, tighten in small additive steps, test each with the emulator against both the Flutter app and Angular.
