import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-355: the profile sheets take their drag handle, shape and colour from
/// the theme (`bottomSheetTheme.showDragHandle: true`), so none of them draws
/// a second handle by hand or turns the theme's off, and no field is filled.
void main() {
  const files = [
    'lib/features/profile/presentation/pages/user_profile_screen.dart',
    'lib/features/profile/presentation/widgets/delegate_phone_change_sheet.dart',
  ];

  for (final path in files) {
    test('$path: one theme drag handle, outlined fields', () {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('showDragHandle: false')));
      // The old hand-drawn handles were 38-40 wide and 4-4.5 high.
      expect(
        RegExp(r'width: 4[0]?,\s*height: 4').hasMatch(src) ||
            RegExp(r'width: 38,\s*height: 4\.5').hasMatch(src),
        isFalse,
      );
      expect(src, isNot(contains('filled: true')));
      expect(src, isNot(contains('Colors.')));
      expect(src, isNot(contains('ElevatedButton')));
    });
  }
}
