/// Button labels for device unbind requests (TAS-153).
///
/// The «فك الأجهزة» page and the device binding section of the security
/// audit use these on web and mobile, so an approve or reject button reads
/// the same in every place a request appears (owner decision, TAS-153).
abstract final class DeviceUnbindLabels {
  /// Approve a pending request and unlock the old device.
  static const String approve = 'فك الارتباط';

  /// Reject a pending request.
  static const String reject = 'رفض';

  /// Confirm button of the reject dialog.
  static const String confirmReject = 'رفض';

  /// Title of the approve confirmation.
  static const String approveTitle = 'فك الارتباط؟';

  /// Title of the reject confirmation.
  static const String rejectTitle = 'رفض الطلب؟';

  /// Cancel button of both confirmations.
  static const String cancel = 'إلغاء';
}
