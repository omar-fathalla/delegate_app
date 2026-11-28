// TAS-363: trusted time for offline attendance (server time + boot clock).
import 'package:delegate_app/core/services/clock/boot_clock.dart';
import 'package:delegate_app/core/services/trusted_time_anchor.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBootClock implements BootClock {
  FakeBootClock(this.ms);
  int? ms;
  @override
  int? elapsedMs() => ms;
}

const hour = 3600 * 1000;
const minute = 60 * 1000;

void main() {
  // Server said 10:00 when the phone had been up 5 h, phone clock agreed.
  final server = DateTime.utc(2026, 11, 28, 8).millisecondsSinceEpoch;
  final anchor = TrustedTimeAnchor(
    serverMs: server,
    bootMs: 5 * hour,
    wallMs: server,
  );

  test('app closed and reopened offline: server time + boot clock', () {
    final c = decideOfflineCapture(
      anchor: anchor,
      bootNowMs: 7 * hour,
      wallNowMs: server + 2 * hour,
    );
    expect(c.trusted, isTrue);
    expect(c.atMs, server + 2 * hour);
    expect(c.syncedAtMs, server);
  });

  test(
    'phone clock moved back: the time stays the server one (small shift)',
    () {
      final c = decideOfflineCapture(
        anchor: anchor,
        bootNowMs: 7 * hour,
        wallNowMs: server + 2 * hour - 5 * minute,
      );
      expect(c.trusted, isTrue);
      expect(c.atMs, server + 2 * hour);
    },
  );

  test(
    'phone clock changed by hours: not trusted (arrival time on the server)',
    () {
      final c = decideOfflineCapture(
        anchor: anchor,
        bootNowMs: 7 * hour,
        wallNowMs: server - 3 * hour,
      );
      expect(c.trusted, isFalse);
      expect(c.issue, OfflineTimeIssue.rebooted);
      expect(c.syncedAtMs, server);
    },
  );

  test('restart: boot clock went back, not trusted', () {
    final c = decideOfflineCapture(
      anchor: anchor,
      bootNowMs: 10 * minute,
      wallNowMs: server + 2 * hour,
    );
    expect(c.trusted, isFalse);
    expect(c.issue, OfflineTimeIssue.rebooted);
  });

  test('restart then a long uptime: caught by the boot moment shift', () {
    final c = decideOfflineCapture(
      anchor: anchor,
      bootNowMs: 6 * hour,
      wallNowMs: server + 30 * hour,
    );
    expect(c.trusted, isFalse);
  });

  test('never synced or no boot clock: not trusted', () {
    expect(
      decideOfflineCapture(
        anchor: null,
        bootNowMs: hour,
        wallNowMs: server,
      ).issue,
      OfflineTimeIssue.noSync,
    );
    expect(
      decideOfflineCapture(
        anchor: anchor,
        bootNowMs: null,
        wallNowMs: server,
      ).issue,
      OfflineTimeIssue.noBootClock,
    );
  });

  test(
    'the anchor survives the app being closed (saved on the phone)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final clock = FakeBootClock(5 * hour);
      final first = TrustedTimeService(
        anchorStore: TrustedTimeAnchorStore(prefs),
        bootClock: clock,
        autoSync: false,
      );
      final serverTime = DateTime.now().add(const Duration(hours: 3));
      await first.recordServerTime(serverTime);
      first.dispose();

      // A new run of the app, offline, 2 s later on the boot clock (the real
      // wall clock moved about the same, so no reboot is suspected).
      clock.ms = 5 * hour + 2000;
      final second = TrustedTimeService(
        anchorStore: TrustedTimeAnchorStore(prefs),
        bootClock: clock,
        autoSync: false,
      );
      final c = second.captureOfflineTime();
      expect(c.trusted, isTrue);
      expect(c.atMs, serverTime.millisecondsSinceEpoch + 2000);
      expect(c.syncedAtMs, serverTime.millisecondsSinceEpoch);
      second.dispose();
    },
  );

  test('a broken saved anchor is ignored', () async {
    SharedPreferences.setMockInitialValues({
      TrustedTimeAnchorStore.key: '{bad',
    });
    final store = TrustedTimeAnchorStore(await SharedPreferences.getInstance());
    expect(store.read(), isNull);
  });

  test('the real boot clock runs on this host', () {
    final ms = BootClock.system().elapsedMs();
    if (ms != null) expect(ms, greaterThan(0));
  });
}
