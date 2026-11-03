import 'package:flutter/material.dart';

import 'google_maps_loader_stub.dart'
    if (dart.library.js_interop) 'google_maps_loader_web.dart'
    as loader;

/// Safely checks if Google Maps SDK is initialized and ready to render
bool get isGoogleMapsAvailable => loader.isGoogleMapsAvailable();

Future<bool>? _ready;

/// Completes when the Maps JS SDK is usable (web), or immediately (mobile).
/// Resolves `false` after [timeout] instead of hanging.
Future<bool> googleMapsReady({Duration timeout = const Duration(seconds: 15)}) {
  if (isGoogleMapsAvailable) return Future.value(true);
  return _ready ??= _poll(timeout).whenComplete(() => _ready = null);
}

Future<bool> _poll(Duration timeout) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (isGoogleMapsAvailable) return true;
  }
  return false;
}

/// Builds [child] only once the Maps SDK is ready; shows a small loader until
/// then. On mobile the SDK is always available, so [child] builds directly.
class GoogleMapsReadyGate extends StatelessWidget {
  final Widget child;

  const GoogleMapsReadyGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (isGoogleMapsAvailable) return child;
    return FutureBuilder<bool>(
      future: googleMapsReady(),
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
        // Ready, or timed out: build the map (same as before this guard).
        return child;
      },
    );
  }
}
