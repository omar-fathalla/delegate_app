import 'package:delegate_app/features/notifications/domain/notification_account_cutoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 10, 22, 0);

  group('notificationAccountCutoff', () {
    test('prefers stored account createdAt over a just-logged-in session stamp', () {
      final stored = DateTime(2026, 1, 1);
      final session = now; // stamped at login
      final cutoff = notificationAccountCutoff(
        storedAccountCreatedAt: stored,
        sessionCreatedAt: session,
        now: now,
      );
      expect(cutoff, stored.subtract(const Duration(minutes: 5)));
    });

    test('ignores a recent session stamp when stored createdAt is missing', () {
      final cutoff = notificationAccountCutoff(
        storedAccountCreatedAt: null,
        sessionCreatedAt: now.subtract(const Duration(minutes: 1)),
        now: now,
      );
      expect(cutoff, isNull);
    });

    test('uses an older session stamp as the real account date', () {
      final session = DateTime(2025, 6, 1);
      final cutoff = notificationAccountCutoff(
        storedAccountCreatedAt: null,
        sessionCreatedAt: session,
        now: now,
      );
      expect(cutoff, session.subtract(const Duration(minutes: 5)));
    });

    test('returns null when both timestamps are missing so nothing is hidden', () {
      expect(
        notificationAccountCutoff(
          storedAccountCreatedAt: null,
          sessionCreatedAt: null,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('shouldHideNotificationForAccountAge', () {
    test('does not hide an older unread alert after a fresh staff login', () {
      final stored = DateTime(2026, 1, 1);
      final alert = now.subtract(const Duration(hours: 2));
      expect(
        shouldHideNotificationForAccountAge(
          notificationCreatedAt: alert,
          storedAccountCreatedAt: stored,
          sessionCreatedAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('hides notifications that predate the stored account by more than grace', () {
      final stored = DateTime(2026, 11, 10, 12);
      final older = stored.subtract(const Duration(minutes: 10));
      expect(
        shouldHideNotificationForAccountAge(
          notificationCreatedAt: older,
          storedAccountCreatedAt: stored,
          sessionCreatedAt: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('shows all notifications when there is no usable cutoff', () {
      expect(
        shouldHideNotificationForAccountAge(
          notificationCreatedAt: now.subtract(const Duration(days: 30)),
          storedAccountCreatedAt: null,
          sessionCreatedAt: now,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
