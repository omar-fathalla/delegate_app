/// Inbox target for a leave-request notification.
///
/// When the delegate has a [supervisorUid], that user is the recipient.
/// Otherwise company supervisors and admins already listen to
/// `delegateUid == supervisor_{companyUID}`, so fall back to that role key
/// instead of writing an empty uid that nobody receives (I2).
String? leaveNotificationDelegateUid({
  required String? supervisorUid,
  required String companyUID,
}) {
  final supervisor = (supervisorUid ?? '').trim();
  if (supervisor.isNotEmpty) return supervisor;
  final company = companyUID.trim();
  if (company.isNotEmpty) return 'supervisor_$company';
  return null;
}
