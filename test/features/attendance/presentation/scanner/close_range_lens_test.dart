// TAS-290: the QR scanner moves to the close-focus lens on iPhone.
import 'package:delegate_app/features/attendance/presentation/scanner/close_range_lens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('closeRangeLensToUse', () {
    test('iOS with a supported close-range lens switches to it', () {
      expect(
        closeRangeLensToUse(
          isIOS: true,
          best: CameraLensType.wide,
          supported: {CameraLensType.normal, CameraLensType.wide},
        ),
        CameraLensType.wide,
      );
    });
    test('no switch on Android, without a lens, or when the lens is missing', () {
      expect(closeRangeLensToUse(isIOS: false, best: CameraLensType.wide, supported: {CameraLensType.wide}), isNull);
      expect(closeRangeLensToUse(isIOS: true, best: null, supported: {CameraLensType.wide}), isNull);
      expect(closeRangeLensToUse(isIOS: true, best: CameraLensType.any, supported: {CameraLensType.any}), isNull);
      expect(closeRangeLensToUse(isIOS: true, best: CameraLensType.wide, supported: {CameraLensType.normal}), isNull);
    });
  });

  group('focusPointFor', () {
    test('maps the tap into 0..1 and clamps', () {
      expect(focusPointFor(const Offset(50, 100), const Size(100, 200)), const Offset(0.5, 0.5));
      expect(focusPointFor(const Offset(-10, 500), const Size(100, 200)), const Offset(0, 1));
      expect(focusPointFor(const Offset(5, 5), Size.zero), const Offset(0.5, 0.5));
    });
  });
}
