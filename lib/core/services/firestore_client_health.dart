import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'page_reload_stub.dart'
    if (dart.library.js_interop) 'page_reload_web.dart'
    as reloader;

/// Detects the Firestore web SDK "client is dead" state.
///
/// After one `INTERNAL ASSERTION FAILED (ID: ca9)` the JS SDK's AsyncQueue is
/// permanently failed and every later get/listen throws `b815` until the page
/// reloads. Instead of leaving blank tabs, we flip [clientDead] once (web
/// only), log a single line, and the app shows a "reload the page" banner.
class FirestoreClientHealth {
  FirestoreClientHealth._();

  static const String reloadMessage = 'حدث خطأ في الاتصال – أعد تحميل الصفحة';

  static final ValueNotifier<bool> clientDead = ValueNotifier<bool>(false);

  @visibleForTesting
  static bool? debugIsWebOverride;
  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

  static bool isClientDeadError(Object? error) {
    if (error == null) return false;
    final text = error.toString();
    // Match only the SDK's own failure texts. Bare ids like 'b815'/'ca9'
    // could appear in unrelated messages (doc ids, hashes) and must not
    // trigger the reload banner.
    return text.contains('INTERNAL ASSERTION FAILED') ||
        text.contains('AsyncQueue is already failed');
  }

  /// Reports an error; returns true if it marked the client dead.
  static bool report(Object? error) {
    if (!_isWeb || !isClientDeadError(error)) return false;
    if (!clientDead.value) {
      debugPrint(
        'FirestoreClientHealth: Firestore web client failed '
        '(INTERNAL ASSERTION). A page reload is required.',
      );
      clientDead.value = true;
    }
    return true;
  }

  static void reloadPage() => reloader.reloadPage();

  @visibleForTesting
  static void debugReset() => clientDead.value = false;
}

/// Overlays a reload banner on top of [child] once the client is dead.
class FirestoreClientHealthBanner extends StatelessWidget {
  const FirestoreClientHealthBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FirestoreClientHealth.clientDead,
      builder: (context, dead, _) {
        if (!dead) return child;
        return Stack(
          children: [
            child,
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            FirestoreClientHealth.reloadMessage,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const Key('firestoreReloadButton'),
                            onPressed: FirestoreClientHealth.reloadPage,
                            icon: const Icon(Icons.refresh),
                            label: const Text(
                              'إعادة تحميل الصفحة',
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
