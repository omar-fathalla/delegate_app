---
name: company_data_isolation
description: Mandatory standard and implementation patterns for Strict Multi-Tenant Company Data Isolation across all features and roles in Tashil delegate_app.
---

# Multi-Tenant Company Data Isolation Standard (قاعدة عزل بيانات الشركات الصارمة)

This skill defines the engineering standard for strict multi-tenant data isolation in `delegate_app`. Every company user (HR, Company Admins, Supervisors, Promoters, Delegates, Accountants, Marketing Promotion, Branches Marketing Managers) must strictly and exclusively access data belonging to their registered company.

---

## 1. Core Principles

1. **Absolute Company Scoping (حظر تسريب بيانات الشركات)**:
   - Any authenticated user associated with a company (`companyUID.isNotEmpty`) MUST NEVER see, count, or interact with data belonging to other companies.
   - Cross-company leakage is considered a critical security violation.

2. **Dual-Layer Enforcement**:
   - **Layer 1 (Firestore Query)**: Always append `.where('companyUID', isEqualTo: user.companyUID)` (or direct subcollection paths like `/organizations/{org}/companies/{comp}/delegates`).
   - **Layer 2 (Client-Side Post-Filter)**: Always filter records in memory (`removeWhere` or `where`) before calculating summary counters or rendering lists to catch any legacy or misattributed documents.

3. **Per-Company Caching**:
   - Cache keys in `SharedPreferences` or local storage MUST include the `companyUID` prefix (e.g. `cached_device_${companyUID}_total_delegates`) to avoid cache contamination between user sessions or organizations.

---

## 2. Role Scoping Matrix

| Role | Scope | Exceptions |
| :--- | :--- | :--- |
| **Super Admin (`superAdmin`)** | Global (All Organizations & Companies) | None |
| **Technical Support (`technicalSupport`)** | Global (All Organizations & Companies) | None |
| **Organization Admin (`organizationAdmin`)** | Organization Root (`organizationUID`) | If a company is explicitly selected, scoped to that `companyUID` |
| **HR Manager (`hr`)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |
| **Company Admin (`admin`)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |
| **Supervisor (`delegate` w/ supervisor position)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |
| **Promoter / Delegate (`delegate`)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |
| **Branches Marketing Manager (`branchesMarketingManager`)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |
| **Accountant (`accountant`)** | Company Only (`companyUID`) | STRICT: Zero access to other companies |

---

## 3. Implementation Patterns

### Pattern A: Firestore Stream with In-Memory Sort
When querying collections without a composite index on `companyUID + timestamp`:
```dart
Query query = FirebaseFirestore.instance.collection('security_audit_logs');
if (isCompanyScoped) {
  query = query.where('companyUID', isEqualTo: user.companyUID);
} else if (isOrgScoped) {
  query = query.where('organizationUID', isEqualTo: user.organizationUID);
}

// In stream builder:
final logs = docs.map((d) => {'docId': d.id, ...d.data()}).toList();

// Post-filter layer:
if (isCompanyScoped) {
  logs.removeWhere((item) => (item['companyUID'] ?? '') != user.companyUID);
}

// Sort descending in memory (0 ms):
logs.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
```

### Pattern B: Direct Subcollection for Delegates
Direct subcollection access is instant and avoids `collectionGroup` composite indexes:
```dart
final snap = await FirebaseFirestore.instance
    .collection('organizations')
    .doc(user.organizationUID)
    .collection('companies')
    .doc(user.companyUID)
    .collection('delegates')
    .get();
```
