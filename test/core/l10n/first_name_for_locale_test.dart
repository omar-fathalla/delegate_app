import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home greeting shows the first name only (user review 27 Nov). A
/// compound Arabic first name keeps both words.
void main() {
  test('first word for a simple name', () {
    expect(firstNameForLocale('محمد أحمد علي', 'x', isArabic: true), 'محمد');
  });
  test('compound first names keep both words', () {
    expect(firstNameForLocale('عبد الرحمن محمد', 'x', isArabic: true), 'عبد الرحمن');
    expect(firstNameForLocale('أبو بكر سالم', 'x', isArabic: true), 'أبو بكر');
  });
  test('falls back when the full name is empty', () {
    expect(firstNameForLocale('', 'مندوب', isArabic: true), 'مندوب');
  });
}
