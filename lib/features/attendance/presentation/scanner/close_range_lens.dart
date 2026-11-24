// TAS-290: on iPhone Pro models the default (wide) camera cannot focus
// closer than ~15–20 cm, so a QR held close stays blurry. The scanner
// switches to the lens that focuses closest (usually the ultra-wide, which
// focuses down to ~2 cm) when the device has it.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:mobile_scanner/mobile_scanner.dart';

/// The lens to switch to, or null to keep the current camera.
CameraLensType? closeRangeLensToUse({
  required bool isIOS,
  required CameraLensType? best,
  required Set<CameraLensType> supported,
}) {
  if (!isIOS || best == null || best == CameraLensType.any) return null;
  if (!supported.contains(best)) return null;
  return best;
}

/// Picks and switches to the close-range lens once the camera runs.
/// Errors are ignored: the default camera still scans.
Future<void> preferCloseRangeLens(MobileScannerController controller) async {
  try {
    final best = await controller.getBestCloseRangeScanningLens();
    final supported = await controller.getSupportedLenses(
      facing: CameraFacing.back,
    );
    final lens = closeRangeLensToUse(
      isIOS: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
      best: best,
      supported: supported,
    );
    if (lens == null) return;
    await controller.switchCamera(
      SelectCamera(facingDirection: CameraFacing.back, lensType: lens),
    );
  } catch (e) {
    debugPrint('Scanner close-range lens: $e');
  }
}

/// Tap position in the preview -> focus point in 0..1 (clamped).
Offset focusPointFor(Offset local, Size size) {
  if (size.width <= 0 || size.height <= 0) return const Offset(0.5, 0.5);
  return Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );
}
