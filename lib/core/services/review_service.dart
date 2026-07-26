import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة مركزية لإدارة التقييم داخل التطبيق (In-App Reviews) والتوجيه للمتجر
class ReviewService {
  final InAppReview _inAppReview;
  final SharedPreferences _prefs;

  static const String _keyLastReviewTimestamp = 'last_review_requested_at';
  static const String _keyActionCount = 'smart_review_action_count';
  static const int _minDaysBetweenPrompts = 30;
  static const int _actionsBeforePrompt = 3;

  ReviewService({
    InAppReview? inAppReview,
    required SharedPreferences prefs,
  })  : _inAppReview = inAppReview ?? InAppReview.instance,
        _prefs = prefs;

  /// طلب التقييم يدويًا أو عبر الزر (مع إمكانية فتح المتجر كبديل)
  Future<void> requestManualReview() async {
    try {
      final isAvailable = await _inAppReview.isAvailable();
      if (isAvailable) {
        await _inAppReview.requestReview();
        await _updateLastReviewTimestamp();
      } else {
        await openStoreListing();
      }
    } catch (e) {
      debugPrint('ReviewService: Error requesting manual review: $e');
      await openStoreListing();
    }
  }

  /// فتح صفحة التطبيق على متجر Google Play أو App Store مباشرة
  Future<void> openStoreListing() async {
    try {
      await _inAppReview.openStoreListing(
        appStoreId: 'com.tashil.delegate',
      );
    } catch (e) {
      debugPrint('ReviewService: Error opening store listing: $e');
    }
  }

  /// طلب التقييم الذكي التلقائي بعد إتمام إجراءات ناجحة (مثل الحضور/الانصراف)
  Future<void> triggerSmartReview() async {
    try {
      final lastTimestamp = _prefs.getInt(_keyLastReviewTimestamp) ?? 0;
      final lastDate = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
      final daysDifference = DateTime.now().difference(lastDate).inDays;

      // تحقق من انقضاء المدة الزمنية الدنيا بين طلبات التقييم
      if (lastTimestamp > 0 && daysDifference < _minDaysBetweenPrompts) {
        return;
      }

      int actionCount = (_prefs.getInt(_keyActionCount) ?? 0) + 1;
      await _prefs.setInt(_keyActionCount, actionCount);

      if (actionCount >= _actionsBeforePrompt) {
        final isAvailable = await _inAppReview.isAvailable();
        if (isAvailable) {
          await _inAppReview.requestReview();
          await _updateLastReviewTimestamp();
          await _prefs.setInt(_keyActionCount, 0);
        }
      }
    } catch (e) {
      debugPrint('ReviewService: Error in smart review trigger: $e');
    }
  }

  Future<void> _updateLastReviewTimestamp() async {
    await _prefs.setInt(
      _keyLastReviewTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
