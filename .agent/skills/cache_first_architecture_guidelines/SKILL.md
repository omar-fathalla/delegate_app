---
name: cache_first_architecture_guidelines
description: Mandatory standard and implementation patterns for Cache-First (Stale-While-Revalidate), Local Caching, and Incremental Background Sync across Flutter BLoC features.
---

# Cache-First & Stale-While-Revalidate Architecture Standard

This skill defines the engineering standard for instant UI rendering, local disk caching, and background network synchronization in `delegate_app`.

---

## 1. Core Principles

1. **Zero Waiting Time (0 ms Initial Render)**:
   - When the user navigates to a screen (e.g. Notifications, Penalties, Photo Reports, Member Directory), the UI MUST immediately load and render the cached data from local persistent storage (`SharedPreferences` or Local DataSource) before hitting the network.
   - Never show blocking full-screen loading spinners if cached data exists.

2. **Silent Background Revalidation (Stale-While-Revalidate)**:
   - In the background, asynchronously query the remote backend (Firestore) for updates or new items added since the last sync.
   - Silently merge new/updated data into the local cache and emit an updated state to the UI without disrupting user interaction.

3. **Data Integrity & Idempotent Deduplication**:
   - Always merge lists using unique entity IDs (e.g. `notificationId`, `penaltyId`, `delegateId`) to prevent duplicates.
   - Synchronize status mutations (Read, Deleted, Approved, Rejected) both locally in cache and remotely on Firestore (Optimistic Dual Write).

---

## 2. Feature Application Matrix

| Feature | Caching Strategy | Live Network Requirement |
| :--- | :--- | :--- |
| **Notifications** | `Cache-First + Background Sync` | Incremental new items check |
| **Photo Reports & Permissions** | `Persistent Disk Cache + Pre-caching` | Background download |
| **Penalties & Infractions** | `Cache-First + Background Sync` | Sync status updates |
| **Delegates & Member Directory** | `Cache-First + Periodic Revalidate` | Cache per organization/company |
| **User Profile & Settings** | `Local Storage / SharedPreferences` | Updated upon edit |
| **Attendance Check-in / Anti-Fraud** | `Live Trusted Time & Geofence` | **STRICT LIVE REQUIRED** (Anti-fraud validation) |
| **Critical Approvals / Deductions** | `Optimistic UI + Direct Firestore Write` | Real-time write with rollback on error |

---

## 3. Implementation Pattern (Clean Architecture)

```dart
// 1. Repository loads cache first, then syncs network in background
Future<Either<Failure, List<T>>> getItems() async {
  // A. Emit / Return local cache immediately
  final localItems = await localDataSource.getCachedItems();
  
  // B. Trigger background remote fetch & cache update
  _fetchAndCacheRemote();
  
  return Right(localItems);
}
```
