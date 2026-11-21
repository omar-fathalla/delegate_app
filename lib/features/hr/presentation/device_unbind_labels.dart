/// Button labels for device unbind requests (TAS-153).
///
/// The «فك الأجهزة» page and the device binding section of the security
/// audit use these, so an approve or reject button reads the same in every
/// place a request appears.
abstract final class DeviceUnbindLabels {
  /// Approve a pending request and unlock the old device.
  static const String approve = 'موافقة وفك الارتباط';

  /// Reject a pending request.
  static const String reject = 'رفض';

  /// Confirm button of the reject dialog.
  static const String confirmReject = 'تأكيد الرفض';

  /// Title of the approve confirmation.
  static const String approveTitle = 'تأكيد الموافقة وفك الارتباط';

  /// Title of the reject confirmation.
  static const String rejectTitle = 'رفض طلب فك الارتباط';

  /// Cancel button of both confirmations.
  static const String cancel = 'إلغاء';
}
