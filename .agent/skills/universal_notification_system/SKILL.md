---
name: universal-notification-system
description: Guidelines, data patterns, and architecture for universal multi-identifier notification resolution, compact card UI, and soft-delete retention across all user roles (Super Admin, Organization Admin, Technical Support, Marketing, Delegates).
---

# Universal Notification System (Clean Architecture + Firestore)

## 📌 Problem Context & Overview
In multi-role applications with multiple authentication channels (Firebase Auth UID, custom session logins like `super-admin-login`, and phone-based logins), users can be targeted in Firestore by:
1. Direct User Auth UID (`delegateUid`)
2. Account Phone Number in various formats (`0150...`, `+20150...`, `phone_0150...`)
3. Linked Firestore `users` document ID
4. Role-based broadcasts (`all`, `super-admin`, `technical_support`, `marketing`, `delegates`)

This skill defines the standard architecture to guarantee 100% notification delivery, unread count accuracy, compact Material 3 presentation, and per-user soft deletion without losing central outbox records.

---

## 🏛️ Layered Architecture Pattern

### 1. Presentation Layer
- **Header & Bell Indicator**:
  Always pass `phoneNumber: delegate.phoneNumber` alongside `delegateUid: delegate.uid` when dispatching `SubscribeToUnreadCount` and `LoadNotifications`:
  ```dart
  BlocProvider(
    create: (_) => di.sl<NotificationBloc>()
      ..add(
        SubscribeToUnreadCount(
          delegateUid: delegate.uid,
          organizationId: delegate.organizationUID,
          phoneNumber: delegate.phoneNumber,
        ),
      ),
  )
  ```
- **Notifications Page**:
  Pass `phoneNumber: delegate.phoneNumber` on initial load, pull-to-refresh, and `MarkAllAsRead`.
- **Compact Card Item (`NotificationListItem`)**:
  - Compact rounded card (14px radius) with type-colored icon container.
  - Formatted full timestamp (`dd/MM/yyyy • hh:mm a`).
  - Truncated 2-line body expanding on tap + auto mark as read.
  - Soft delete button 🗑️ and swipe-to-delete with confirmation dialog.

---

### 2. BLoC & Events Layer
All notification events must accept `String? phoneNumber`:
- `LoadNotifications({required delegateUid, required organizationId, this.phoneNumber})`
- `SubscribeToUnreadCount({required delegateUid, required organizationId, this.phoneNumber})`
- `MarkAsRead({required notificationId, required delegateUid, required organizationId, this.phoneNumber})`
- `MarkAllAsRead({required delegateUid, required organizationId, this.phoneNumber})`
- `DeleteNotificationRequested({required notificationId, required delegateUid, required organizationId, this.phoneNumber})`

---

### 3. Remote Data Source Lookup Algorithm
When querying Firestore `notifications`:
```dart
// 1. Direct UID match
_collection.where('delegateUid', isEqualTo: delegateUid);

// 2. Global broadcast match
_collection.where('delegateUid', isEqualTo: 'all');

// 3. Phone-tagged UID match
_collection.where('delegateUid', isEqualTo: 'phone_$delegateUid');

// 4. Role / Admin Fallback match
if (delegateUid == 'super-admin-login' || delegateUid.contains('super')) {
  // Query users where role == 'super-admin' and match their UIDs & phones
}

// 5. Phone Variations Multi-Query:
// ['01508899965', '+201508899965', '1508899965', '+971...']
// For each phone variation:
// a) Query `users` by phoneNumber -> match user doc IDs
// b) Query notifications where phoneNumber == p
// c) Query notifications where delegateUid == p
// d) Query notifications where delegateUid == 'phone_$p'

// 6. Soft Delete Filter:
// Exclude if doc['deletedBy'].contains(delegateUid) or doc['deletedBy'].contains(phoneNumber)

// 7. Chronological Sort (Newest First):
// docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
```

---

### 4. Soft Delete vs Central Outbox Retention
- **Personal Inbox Deletion**:
  When a user deletes a notification, add their UID to the `deletedBy` array in the `notifications` collection:
  ```dart
  _collection.doc(notificationId).update({
    'deletedBy': FieldValue.arrayUnion([userUid]),
  });
  ```
- **Outbox Integrity**:
  The central broadcast log in `sent_notifications/{broadcastId}` remains untouched, preserving full delivery metrics and read receipts for technical support and administrators.

---

### 5. Google Cloud & Firebase Functions Deployment Isolation
- **Targeted Deployment Only**: The GCP project (`practice-firebase-72df1` / `Tashil`) hosts 22+ active production Cloud Run / Functions for the Web portal and external systems.
- **Codebase Scope**: In `firebase.json`, notifications must be encapsulated under `codebase: "tashil-mobile-notifications"`.
- **Safe Command**: Always deploy using targeted codebase or function names:
  `firebase deploy --only functions:tashil-mobile-notifications`
  Never execute broad unscoped `firebase deploy --only functions` to prevent deleting or altering existing web services.
