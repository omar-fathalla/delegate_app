import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-72: delegates cannot edit their name / email / phone on the delegate
/// documents under the rules; the screen hides those edit buttons for them.
void main() {
  test('delegates do not get the identity edit buttons', () {
    expect(profileIdentityEditable(UserRole.delegate), isFalse);
  });

  test('staff roles and unknown profiles keep them', () {
    for (final role in UserRole.values.where((r) => r != UserRole.delegate)) {
      expect(profileIdentityEditable(role), isTrue, reason: role.name);
    }
    expect(profileIdentityEditable(null), isTrue);
  });
}
