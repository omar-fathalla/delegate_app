/// Payload for the `sendStaffNotification` callable (TAS-216).
///
/// The server reads the sender's role, organization and company from
/// `users/{uid}`; this payload only says what to send and to whom. Keep the
/// target kinds in sync with `functions/src/send_staff_notification_logic.ts`.
Map<String, dynamic> buildSendStaffNotificationPayload({
  required String title,
  required String body,
  required String type,
  required String audience,
  required String role,
  required String? organizationUid,
  required String phone,
}) {
  final Map<String, dynamic> target;
  switch (audience) {
    case 'org':
      target = {'kind': 'org', 'organizationUID': organizationUid ?? ''};
      break;
    case 'role':
      target = {'kind': 'role', 'role': role};
      break;
    case 'user':
      target = {'kind': 'user', 'phone': phone.trim()};
      break;
    case 'all':
    default:
      target = {'kind': 'all'};
  }
  return {
    'title': title.trim(),
    'body': body.trim(),
    'type': type,
    'target': target,
  };
}

/// Arabic message for a callable error `reason` (from HttpsError details).
String sendStaffNotificationErrorMessage(String code, String? reason) {
  switch (reason) {
    case 'broadcast_global_only':
      return 'البث العام لجميع المستخدمين متاح للإدارة العليا والدعم الفني فقط.';
    case 'type_not_allowed':
      return 'إشعارات تحديث التطبيق متاحة للإدارة العليا والدعم الفني فقط.';
    case 'out_of_scope':
      return 'لا يمكنك الإرسال خارج نطاق شركتك أو منظمتك.';
    case 'delegate_not_allowed':
    case 'role_not_allowed':
    case 'no_scope':
    case 'no_profile':
      return 'ليست لديك صلاحية إرسال الإشعارات.';
    case 'not_found':
      return 'لم يتم العثور على مستخدم بهذا الرقم داخل نطاقك.';
    case 'invalid_phone':
      return 'رقم الهاتف غير صحيح.';
    case 'too_many_recipients':
      return 'عدد المستلمين كبير جداً لإرسال واحد. اختر فئة أو نطاقاً أصغر.';
    case 'text_too_long':
      return 'العنوان أو نص الإشعار طويل جداً.';
  }
  if (code == 'permission-denied') return 'ليست لديك صلاحية لهذا الإرسال.';
  if (code == 'unauthenticated') return 'يرجى تسجيل الدخول مرة أخرى.';
  return 'تعذر إرسال الإشعار. حاول مرة أخرى.';
}
