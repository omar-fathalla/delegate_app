# Super-admin password account

Staff login looks up `users` by phone, reads that document's `email`, and calls `FirebaseAuth.signInWithEmailAndPassword`. The app has no built-in email, uid, or password. Production Auth has no user for the address the old client hardcoded, so that address cannot be used unless someone creates it.

`isSuperAdmin()` reads `users/{request.auth.uid}.role`. The canonical value is `super-admin`. Legacy `super_admin`, `superadmin`, and `superAdmin` still grant access until `migrate-super-admin-role.js` runs. The Firestore document id must be the Firebase Auth uid. Anonymous sign-in is denied.

Do not run the script as part of deploy. `functions/scripts/create-super-admin-user.js` is not imported by `index.ts`. It does not create the Auth user and it does not take a password.

## Console setup

1. In the Firebase console, Authentication, add an email/password user. Choose the email and password there. Copy the new user's uid.
2. Create or update Firestore document `users/{that uid}` with:
   - `uid`: the same Auth uid
   - `phoneNumber`: `01508899965`
   - `role`: `super-admin`
   - `email`: the email of the Auth user from step 1
   - `displayName` / `fullName`: `Omar Fathalla`
   - `organizationUID` and `organizationName`: the organization this account should operate in
   - `companyUID` and `companyName`: the company, when company-scoped screens should show one
3. No national ID is required for this password login.
4. Sign in from the app with phone `01508899965` and the Auth password. A wrong password is rejected by Firebase Auth.

The removed client fallback used to invent `organizationUID` `PiioBFgxaHAeuRdjlDgj`, `organizationName` `fathalla market`, `companyUID` `s4J0c33Ctom3w64lbcKU`, and `companyName` `admin` when no document was found. Put those values on the real document only if they are still the right organization and company. The app no longer fills them in.

If a `users` document for this phone already exists under a different id, rules still check `users/{Auth uid}`. The document id has to be the Auth uid. A stored `role` of `super_admin` still signs in inside the app and is treated as super-admin by the rules until the migration script rewrites it. New writes must use `super-admin`.

Staff phone lookup no longer depends on a public `users` read. Deploy `staffPhoneLookup` before the tightened rules. Until that function is deployed, the app falls back to the `users` phone query, which the tightened rules reject.

## Optional script

From `functions/`, with Application Default Credentials only for `--apply`:

```bash
node scripts/create-super-admin-user.js \
  --uid AUTH_UID \
  --email person@example.com \
  --organization-uid ORG_ID \
  --organization-name "Org name" \
  --company-uid COMPANY_ID \
  --company-name "Company"

node scripts/create-super-admin-user.js \
  --uid AUTH_UID \
  --email person@example.com \
  --organization-uid ORG_ID \
  --organization-name "Org name" \
  --apply
```

The first command prints `users/{uid}` and the field map. `--apply` merges that map into the document. Phone defaults to `01508899965` and the display name defaults to `Omar Fathalla`; pass `--phone` or `--display-name` to override either. Running `--apply` against production is a separate, reviewed operation.
