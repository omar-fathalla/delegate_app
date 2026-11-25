import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';

class FeedbackModel extends FeedbackEntity {
  const FeedbackModel({
    super.id,
    required super.userId,
    required super.userName,
    required super.userEmail,
    required super.type,
    required super.content,
    super.screenshotUrl,
    super.status,
    required super.createdAt,
    super.updatedAt,
    super.adminResponse,
  });

  /// تحويل من JSON إلى Model
  factory FeedbackModel.fromJson(Map<String, dynamic> json, String id) {
    return FeedbackModel(
      id: id,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      userEmail: json['userEmail'] as String,
      type: FeedbackType.values.firstWhere(
        (e) => e.value == json['type'],
        orElse: () => FeedbackType.other,
      ),
      content: json['content'] as String,
      // TAS-42: new docs carry the Storage path; old ones only a URL.
      screenshotUrl: _screenshotRef(json),
      status: FeedbackStatus.values.firstWhere(
        (e) => e.value == json['status'],
        orElse: () => FeedbackStatus.pending,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      adminResponse: json['adminResponse'] as String?,
    );
  }

  /// تحويل من Model إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'type': type.value,
      'content': content,
      if (StorageMediaRef.isStoragePath(screenshotUrl))
        'screenshotPath': screenshotUrl
      else
        'screenshotUrl': screenshotUrl,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'adminResponse': adminResponse,
    };
  }

  static String? _screenshotRef(Map<String, dynamic> json) {
    final ref = StorageMediaRef.pick(
      path: json['screenshotPath'],
      url: json['screenshotUrl'],
    );
    return ref.isEmpty ? null : ref;
  }
}
