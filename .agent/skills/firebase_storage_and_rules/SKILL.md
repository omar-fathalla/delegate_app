---
name: firebase_storage_and_rules
description: Guidelines and mandatory rules for Firebase Storage paths, upload security rules, and Firestore collection permissions across all 9 user roles (Delegates, Supervisors, Admins, Marketing, etc.).
---

# Firebase Storage & Security Rules Skill

This skill defines mandatory architecture, rules, and procedures for file uploads and Firebase Storage access in `delegate_app`.

---

## 1. Storage Upload Paths Matrix

Every file upload path in the application MUST be registered and permitted in `storage.rules`:

| Feature | Storage Path | Allowed Roles / Access |
| :--- | :--- | :--- |
| **User Feedbacks & Suggestions** | `/feedback_screenshots/{fileName}` | All Authenticated Users (`isAuthenticated()`) |
| **Photo Permissions & Reports** | `/organizations/{orgId}/companies/{compId}/permissions/{permissionId}/{photoId}` | Authenticated Users (`isAuthenticated()`) |
| **Organization Files & Docs** | `/organizations/{orgId}/{allPaths=**}` | Authenticated Users with organization access |
| **Company Documents & Logos** | `/companies/{compId}/{allPaths=**}` | Authenticated Users with company access |
| **Delegate Documents & Photos** | `/delegates/{delegateId}/{allPaths=**}` | Authenticated Users |
| **Penalties & Violations Proof** | `/penalties/{allPaths=**}` | Authenticated Users |
| **Guide & Tutorial Videos** | `/guide-videos/{fileName}` | Read: Authenticated / Write: Super Admin |
| **Public Assets** | `/public/{allPaths=**}` | Read: Public (`true`) / Write: Authenticated |

---

## 2. Mandatory Rules Principles

1. **Never Rely on Un-deployed Rules**:
   - Whenever a new feature involves uploading files (images, PDFs, screenshots), verify that `storage.rules` contains the matching `match` block.
   - Deploy rules immediately using `npx -y firebase-tools@latest deploy --only storage,firestore:rules`.

2. **Universal Feedback Uploads (All 9 Roles)**:
   - Feedback submission and screenshot attachment must work seamlessly for all roles:
     - Delegate (`UserRole.delegate`)
     - Promoter (`UserRole.promoter`)
     - Company Supervisor (`UserRole.admin`)
     - General Manager (`UserRole.organizationAdmin`)
     - Super Admin (`UserRole.superAdmin`)
     - Marketing (`UserRole.marketing`)
     - Branches Marketing Manager (`UserRole.branchesMarketingManager`)
     - Technical Support (`UserRole.technicalSupport`)
     - Marketing Promotion (`UserRole.marketingPromotion`)

3. **Fallback Match Block**:
   - `storage.rules` includes a fallback authenticated match block `match /{allPaths=**} { allow read, write: if isAuthenticated(); }` to prevent sudden breakage for unanticipated sub-paths.

4. **Firestore Rules for Feedbacks**:
   - `match /feedbacks/{feedbackId} { allow read, write: if isAuthenticated(); }` allows any authenticated user to create feedback and attach screenshot URLs.
