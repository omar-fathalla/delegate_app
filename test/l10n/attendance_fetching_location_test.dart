import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// TAS-341: the QR check-in toast was a hard-coded English string.
void main() {
  test('fetching-location toast is localized', () {
    expect(
      lookupAppLocalizations(const Locale('ar')).attFetchingLocation,
      'جاري تحديد موقعك...',
    );
    final src = File(
      'lib/features/attendance/presentation/pages/attendance_screen.dart',
    ).readAsStringSync();
    expect(src.contains("'Fetching location...'"), isFalse);
  });
}
