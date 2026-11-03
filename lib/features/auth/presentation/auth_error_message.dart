import 'package:delegate_app/l10n/app_localizations.dart';

/// Maps stable auth failure codes to the active locale.
///
/// Unknown codes keep the message already produced by the repository, which
/// is how older Arabic-only failures still surface.
String localizedAuthError(
  AppLocalizations l10n, {
  required String message,
  String? code,
}) {
  switch (code) {
    case 'invalid_credentials':
      return l10n.invalidLoginCredentials;
    case 'account_inactive':
      return l10n.delegateAccountInactive;
    case 'rate_limited':
      return l10n.tooManyLoginAttempts;
    case 'invalid_phone':
      return l10n.invalidMobileNumber;
    case 'invalid_national_id':
      return l10n.invalidNationalId;
    case 'network':
      return l10n.loginNetworkError;
    case 'unavailable':
      return l10n.loginTemporarilyUnavailable;
    default:
      return message;
  }
}
