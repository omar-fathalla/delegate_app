import 'dart:developer' as developer;

/// Ghost guard (18 Nov 2026).
///
/// A delegate link doc (organizations/{o}/companies/{c}/delegates/{id}) with
/// no name, national ID and phone is a "ghost": old app builds (1.11) wrote
/// only the bound device with set(merge: true) and re-created delegates that
/// had been deleted. Ghosts rendered as «؟» rows with no name or phone in the
/// payroll, attendance and dashboard counts. Keep this list in sync with
/// functions/src/delegate_identity.ts.
const List<String> kDelegateNameFields = [
  'fullName', 'firstName', 'middleName', 'lastName', 'name',
];
const List<String> kDelegateNationalIdFields = [
  'nationalityID', 'nationalityId', 'nationalId', 'nationalID', 'national_id', 'idNumber',
];
const List<String> kDelegatePhoneFields = [
  'phoneNumber', 'phone', 'mobile', 'mobileNumber',
];

bool _filled(Object? v) {
  if (v is String) return v.trim().isNotEmpty;
  if (v is num) return v.isFinite;
  return false;
}

/// True when the raw delegate doc has a name, a national ID or a phone.
bool delegateDocHasIdentity(Map<String, dynamic>? data) {
  if (data == null) return false;
  for (final f in kDelegateNameFields) {
    if (_filled(data[f])) return true;
  }
  for (final f in kDelegateNationalIdFields) {
    if (_filled(data[f])) return true;
  }
  for (final f in kDelegatePhoneFields) {
    if (_filled(data[f])) return true;
  }
  return false;
}

/// Logs a skipped ghost doc once per path, so the list stays quiet on rebuilds.
final Set<String> _loggedGhostPaths = <String>{};

void logSkippedGhostDelegate(String path) {
  if (_loggedGhostPaths.add(path)) {
    developer.log('Skipped delegate doc without identity (ghost): $path',
        name: 'delegate_identity');
  }
}
