import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'google_maps_loader_stub.dart'
    if (dart.library.js_interop) 'google_maps_loader_web.dart' as loader;

/// Test seam: overrides the platform availability check when set.
@visibleForTesting
bool Function()? googleMapsAvailabilityOverride;

/// Safely checks if Google Maps SDK is initialized and ready to render
bool get isGoogleMapsAvailable =>
    googleMapsAvailabilityOverride?.call() ?? loader.isGoogleMapsAvailable();

Future<bool>? _ready;

/// Test seam: replaces the web script reload when set.
@visibleForTesting
void Function()? googleMapsReloadOverride;

/// Web: re-inject the Maps <script> (same src/key as index.html). Mobile: no-op.
void reloadGoogleMapsScript() =>
    (googleMapsReloadOverride ?? loader.reloadGoogleMapsScript)();

/// Completes when the Maps JS SDK is usable (web), or immediately (mobile).
/// Resolves `false` after [timeout] instead of hanging.
Future<bool> googleMapsReady({
  Duration timeout = const Duration(seconds: 15),
}) {
  if (isGoogleMapsAvailable) return Future.value(true);
  return _ready ??= _poll(timeout).whenComplete(() => _ready = null);
}

Future<bool> _poll(Duration timeout) async {
  const step = Duration(milliseconds: 100);
  final steps = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i < steps; i++) {
    await Future<void>.delayed(step);
    if (isGoogleMapsAvailable) return true;
  }
  return false;
}

/// Builds [child] only once the Maps SDK is ready; shows a small loader until
/// then, and «الخريطة غير متاحة» with a retry if it never loads. On mobile the
/// SDK is always available, so [child] builds directly.
class GoogleMapsReadyGate extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  const GoogleMapsReadyGate({
    super.key,
    required this.child,
    this.timeout = const Duration(seconds: 15),
  });

  @override
  State<GoogleMapsReadyGate> createState() => _GoogleMapsReadyGateState();
}

class _GoogleMapsReadyGateState extends State<GoogleMapsReadyGate> {
  Future<bool>? _wait;

  @override
  void initState() {
    super.initState();
    if (!isGoogleMapsAvailable) _wait = googleMapsReady(timeout: widget.timeout);
  }

  void _retry() {
    if (!isGoogleMapsAvailable) reloadGoogleMapsScript();
    setState(() {
      _wait = isGoogleMapsAvailable
          ? null
          : googleMapsReady(timeout: widget.timeout);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    if (wait == null) return widget.child;
    return FutureBuilder<bool>(
      future: wait,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        if (snap.data == true) return widget.child;
        final l10n = AppLocalizations.of(context);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                l10n?.mapUnavailable ?? 'الخريطة غير متاحة',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('maps_gate_retry'),
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n?.mapRetry ?? 'إعادة المحاولة'),
              ),
            ],
          ),
        );
      },
    );
  }
}
