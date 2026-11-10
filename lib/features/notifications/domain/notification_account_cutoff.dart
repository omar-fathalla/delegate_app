/// Cutoff used to hide notifications that predate the account itself.
///
/// A staff login used to stamp [sessionCreatedAt] as `DateTime.now()`, which
/// hid unread NID alerts older than five minutes before the current session.
/// Prefer the persisted account timestamp. Ignore a session stamp that is
/// clearly "just logged in" so the bell still lists older unread alerts.
/// Local push popups are unchanged (they only fire for new FCM messages).
DateTime? notificationAccountCutoff({
  DateTime? storedAccountCreatedAt,
  DateTime? sessionCreatedAt,
  DateTime? now,
  Duration recentSessionWindow = const Duration(minutes: 15),
  Duration grace = const Duration(minutes: 5),
}) {
  final clock = now ?? DateTime.now();
  DateTime? account = storedAccountCreatedAt;
  if (account == null && sessionCreatedAt != null) {
    final isRecentLogin =
        !sessionCreatedAt.isBefore(clock.subtract(recentSessionWindow));
    if (!isRecentLogin) {
      account = sessionCreatedAt;
    }
  }
  if (account == null) return null;
  return account.subtract(grace);
}

bool shouldHideNotificationForAccountAge({
  required DateTime notificationCreatedAt,
  DateTime? storedAccountCreatedAt,
  DateTime? sessionCreatedAt,
  DateTime? now,
}) {
  final cutoff = notificationAccountCutoff(
    storedAccountCreatedAt: storedAccountCreatedAt,
    sessionCreatedAt: sessionCreatedAt,
    now: now,
  );
  if (cutoff == null) return false;
  return notificationCreatedAt.isBefore(cutoff);
}
