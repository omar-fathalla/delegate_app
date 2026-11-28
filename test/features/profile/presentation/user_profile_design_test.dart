import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-387 (user review 27 Nov 2026): the profile follows the playground.
/// The screen reads Firebase directly, so the layout is guarded on the
/// source: a compact header (name in titleMedium, role and organisation as
/// icon + text), official list items, section titles outside the cards, a
/// skeleton while loading, the password as a list item. The Maestro id on
/// the phone value stays.
void main() {
  final src = File(
    'lib/features/profile/presentation/pages/user_profile_screen.dart',
  ).readAsStringSync();
  final header = src.substring(
    src.indexOf('Widget _buildProfileHeader('),
    src.indexOf('Widget _sectionTitle('),
  );

  test('header: compact, no bold headline, role is not a chip', () {
    expect(header, contains("Key('profile_name')"));
    expect(header, contains('style: tt.titleMedium'));
    expect(header, isNot(contains('headlineSmall?.copyWith(\n                fontWeight')));
    expect(header, isNot(contains('secondaryContainer')));
    expect(header, contains('Skeleton.circle'));
    expect(header, isNot(contains('CircularProgressIndicator')));
  });

  test('info rows are ListTiles; password is a list item; Maestro id kept', () {
    expect(src, contains('return ListTile('));
    expect(src, contains("Key('profileChangePasswordButton')"));
    expect(src, isNot(contains('FilledButton.tonalIcon(\n                key: const Key(\'profileChangePasswordButton\')')));
    expect(src, contains("'tashil_profile_phone_value'"));
    expect(src, contains("Key('profile_skeleton')"));
    expect(src, isNot(contains('Center(child: CircularProgressIndicator())')));
  });

  test('work details: code (copy), masked national ID, city, chains, join date',
      () {
    final work = src.substring(
      src.indexOf('List<Widget> _buildWorkInfo('),
      src.indexOf('// ─── Security Card'),
    );
    expect(work, contains("Key('profile_work_card')"));
    expect(work, contains("Key('profile_delegate_code')"));
    expect(work, contains('Clipboard.setData'));
    expect(work, contains("Key('profile_national_id')"));
    expect(work, contains('Bidi.ltr(_showNationalId ? id : maskedId)'));
    expect(work, contains("Key('profile_chains')"));
    expect(work, contains("Key('profile_join_date')"));
    // Only for a field delegate / supervisor.
    expect(work, contains('delegate.role != UserRole.delegate'));
  });

  test('TAS-366: «مرتبي» list item for delegate tokens only', () {
    expect(src, contains("Key('profileMySalaryTile')"));
    expect(src, contains('if (effectiveDelegate?.role == UserRole.delegate) ...['));
    expect(src, contains('DelegateMySalaryScreen(delegate: delegate)'));
  });
}
