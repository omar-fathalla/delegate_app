---
description: Build, maintain, and query notifications with universal multi-identifier resolution and per-user soft delete.
---

# Notification System Workflow

This workflow guides you through maintaining or extending the notifications feature in Tashil.

## Steps:

1. **Verify Notification Events**:
   - Ensure `phoneNumber` is accepted in all BLoC events (`LoadNotifications`, `SubscribeToUnreadCount`, `MarkAsRead`, etc.).

2. **Verify Multi-Identifier Lookup**:
   - Check `NotificationRemoteDataSourceImpl.getNotifications`:
     - Resolves by `delegateUid` (Auth UID & custom logins).
     - Resolves by `all` (general broadcasts).
     - Resolves by phone variations (`+20...`, `01...`, etc.).
     - Cross-references Firestore `users` documents.
     - Role fallbacks (`super-admin-login`, `technical_support`, etc.).

3. **Verify Presentation Layer**:
   - Header/Bell widget passes `phoneNumber: delegate.phoneNumber`.
   - `NotificationsPage` displays compact `NotificationListItem` with full date/time formatting.

4. **Verify Soft Deletion**:
   - Uses `FieldValue.arrayUnion([userUid])` on `deletedBy` field in `notifications` collection.
   - Preserves broadcast audit log in `sent_notifications`.
