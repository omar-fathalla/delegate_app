import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/presentation/auth_error_message.dart';
import 'package:delegate_app/l10n/app_localizations_ar.dart';
import 'package:delegate_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-5: a blocked or offline staff login must not look like a wrong password.
void main() {
  final ar = AppLocalizationsAr();
  final en = AppLocalizationsEn();

  test('too-many-requests maps to rate_limited', () {
    final f = AuthRemoteDataSourceImpl.mapStaffSignInError('too-many-requests');
    expect(f?.code, 'rate_limited');
    expect(localizedAuthError(ar, message: f!.message, code: f.code),
        'محاولات كثيرة، حاول لاحقاً');
  });

  test('network-request-failed maps to network', () {
    final f =
        AuthRemoteDataSourceImpl.mapStaffSignInError('network-request-failed');
    expect(f?.code, 'network');
    expect(localizedAuthError(ar, message: f!.message, code: f.code),
        'تعذّر الاتصال، تأكد من الإنترنت');
    expect(localizedAuthError(en, message: f.message, code: f.code),
        contains('internet'));
  });

  test('credential misses stay a plain false (no account-existence leak)', () {
    for (final code in [
      'wrong-password',
      'user-not-found',
      'invalid-credential',
      'invalid-email',
      'user-disabled',
    ]) {
      expect(AuthRemoteDataSourceImpl.mapStaffSignInError(code), isNull,
          reason: code);
    }
  });

  test('delegateLoginV2 429 (resource-exhausted) shows the same message', () {
    expect(localizedAuthError(ar, message: '', code: 'rate_limited'),
        'محاولات كثيرة، حاول لاحقاً');
  });
}
