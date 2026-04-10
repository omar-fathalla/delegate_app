---
description: Verify the project for analysis errors, schema consistency, and anti-fraud compliance.
---

# Project Verification Checklist

Run this workflow before committing or merging to ensure project health.

## 1. Static Analysis

// turbo
```
flutter analyze
```

Fix all reported issues. Do NOT suppress lints with `// ignore:` without documented justification.

## 2. Run Tests

// turbo
```
flutter test
```

All tests must pass.

## 3. Schema Consistency Check

Manually verify that all Dart models match the existing Firestore schema:

- [ ] All JSON keys use **camelCase** (not snake_case)
- [ ] `nationalityID` uses capital "ID" (not `nationalityId` or `nationality_id`)
- [ ] `organizationUID` and `companyUID` use capital "UID"
- [ ] `birthDate` uses `Timestamp` type (not String)
- [ ] Document valid keys match: `personalPhoto`, `nationalityId`, `authorizationLetter`, `insuranceLetter`, `healthCertificate`, `paymentReceipt`

## 4. Anti-Fraud Compliance

Search the codebase for violations:

```
# Should find ZERO results for attendance-related DateTime.now()
grep -r "DateTime.now()" lib/features/attendance/
```

- [ ] All attendance timestamps use `FieldValue.serverTimestamp()`
- [ ] Location is verified before check-in/check-out
- [ ] Mock location detection is active (`position.isMocked`)

## 5. Collection Path Audit

- [ ] No code accesses root-level `/delegates` collection
- [ ] All paths follow: `/organizations/{orgId}/companies/{compId}/delegates/{uid}`
- [ ] User data is fetched from `/users/{uid}` to get `orgId` and `compId`

## 6. Security Audit

- [ ] No hardcoded API keys or secrets in source code
- [ ] No `print()` statements (use `debugPrint()` only)
- [ ] Delegates can only access their own data (`uid == currentUser.uid`)

## 7. Build Check

// turbo
```
flutter build apk --debug
```

Ensure the build completes without errors.
