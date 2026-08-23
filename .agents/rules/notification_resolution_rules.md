# Notification System Rules & Conventions

## 1. Multi-Identifier Resolution Rule
- **Mandatory Phone Passing**: When calling any notification event (`LoadNotifications`, `SubscribeToUnreadCount`, `MarkAsRead`, `MarkAllAsRead`, `DeleteNotificationRequested`), always pass `phoneNumber: delegate.phoneNumber` alongside `delegateUid: delegate.uid`.
- **DataSource Queries**: In `NotificationRemoteDataSource`, queries must resolve notifications via:
  1. Direct `delegateUid` match.
  2. Broadcast `all` match.
  3. Phone tag (`phone_$delegateUid` and `phone_$phoneNumber`).
  4. Phone variations (`01...`, `+201...`, without leading 0, etc.).
  5. Cross-referencing `users` collection to resolve phone number to Firestore user document UIDs.
  6. Role matching for administrative logins (e.g. `super-admin-login` -> `users` where `role == 'super-admin'`).

## 2. Chronological Ordering Rule
- Notifications must always be sorted descending by creation time (`createdAt`) so newest notifications appear at the top.

## 3. Per-User Soft-Delete & Outbox Retention Rule
- When a user deletes a notification, the operation MUST only append the user's identifier to the `deletedBy` array in the `notifications` collection doc.
- The corresponding entry in `sent_notifications` MUST NOT be deleted, preserving delivery and read receipt history for administrators.

## 4. Compact Card UI Standards
- Notification cards (`NotificationListItem`) must remain compact by default (max 2 lines of preview).
- Every card must display:
  - Colored type icon.
  - Title and unread indicator dot.
  - Full timestamp (`dd/MM/yyyy • hh:mm a`).
  - Delete button 🗑️ with confirmation dialog.
- Expanding the card or tapping it marks it as read automatically.
