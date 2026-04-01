import 'package:equatable/equatable.dart';

/// أنواع المقترحات المتاحة
enum FeedbackType {
  featureRequest('feature_request', '💡 فكرة تطويرية', 'Feature Request'),
  bugReport('bug_report', '🐛 الإبلاغ عن مشكلة', 'Bug Report'),
  generalQuestion('general_question', '❓ استفسار عام', 'General Question'),
  improvement('improvement', '⭐ تحسين', 'Improvement'),
  other('other', '📝 أخرى', 'Other');

  final String value;
  final String labelAr;
  final String labelEn;

  const FeedbackType(this.value, this.labelAr, this.labelEn);

  String getLabel(bool isArabic) => isArabic ? labelAr : labelEn;
}

/// حالة المقترح
enum FeedbackStatus {
  pending('pending', 'قيد المراجعة', 'Pending'),
  reviewed('reviewed', 'تمت المراجعة', 'Reviewed'),
  inProgress('in_progress', 'قيد التنفيذ', 'In Progress'),
  resolved('resolved', 'تم الحل', 'Resolved'),
  rejected('rejected', 'مرفوض', 'Rejected');

  final String value;
  final String labelAr;
  final String labelEn;

  const FeedbackStatus(this.value, this.labelAr, this.labelEn);

  String getLabel(bool isArabic) => isArabic ? labelAr : labelEn;
}

/// كيان المقترح
class FeedbackEntity extends Equatable {
  final String? id;
  final String userId;
  final String userName;
  final String userEmail;
  final FeedbackType type;
  final String content;
  final String? screenshotUrl;
  final FeedbackStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? adminResponse;

  const FeedbackEntity({
    this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.type,
    required this.content,
    this.screenshotUrl,
    this.status = FeedbackStatus.pending,
    required this.createdAt,
    this.updatedAt,
    this.adminResponse,
  });

  @override
  List<Object?> get props => [
    id,
    userId,
    userName,
    userEmail,
    type,
    content,
    screenshotUrl,
    status,
    createdAt,
    updatedAt,
    adminResponse,
  ];
}
