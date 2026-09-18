---
name: gcp_and_firebase_functions_isolation
description: Mandatory standards and rules for zero-conflict codebase isolation when deploying or modifying Google Cloud Functions, Cloud Run, and Firebase backend resources in shared GCP environments.
---

# Google Cloud & Firebase Functions Isolation Standard

## 1. Architecture Overview
- **Project ID**: `practice-firebase-72df1` (Tashil)
- **Shared Architecture**: This Google Cloud / Firebase project hosts over 22+ active production Cloud Functions and Cloud Run services supporting the Web portal, CRM, and administrative services (e.g., `approvecreaterequest`, `createorganization`, `deleteuser`, `verifyrecaptcha`, etc.).
- **Mobile Codebase**: All mobile-related Cloud Functions are strictly scoped to the codebase `tashil-mobile-notifications`.

## 2. Mandatory Isolation Configuration
In `firebase.json`:
```json
{
  "functions": [
    {
      "codebase": "tashil-mobile-notifications",
      "source": "functions",
      "runtime": "nodejs20"
    }
  ]
}
```

## 3. Strict Deployment Rules
1. **NEVER run blanket deploy**:
   - ❌ `firebase deploy --only functions` is STRICTLY PROHIBITED.
2. **ALWAYS use targeted codebase or function-level deployment**:
   - ✅ `npx firebase-tools deploy --only functions:tashil-mobile-notifications`
   - ✅ `npx firebase-tools deploy --only functions:tashil-mobile-notifications:onTaskCreated`
3. **Zero Deletion / Zero Edit Rule**:
   - Never delete, overwrite, or mutate any Cloud Function or Cloud Run service outside `tashil-mobile-notifications`.
   - All deployments must be additive and isolated.
