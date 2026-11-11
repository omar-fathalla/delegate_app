import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'dart:io';

abstract class FeedbackRemoteDataSource {
  Future<void> submitFeedback(FeedbackModel feedback, File? screenshot);
  Future<List<FeedbackModel>> getUserFeedbacks(String userId);
  Future<FeedbackModel> getFeedbackById(String feedbackId);
  Future<List<FeedbackModel>> getAllFeedbacks();
  Future<void> updateFeedbackStatus({
    required String feedbackId,
    required FeedbackStatus status,
    String? adminResponse,
  });
  Future<void> deleteFeedback(String feedbackId);
}

class FeedbackRemoteDataSourceImpl implements FeedbackRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  FeedbackRemoteDataSourceImpl({
    required this.firestore,
    required this.storage,
  });

  @override
  Future<void> submitFeedback(FeedbackModel feedback, File? screenshot) async {
    String? screenshotUrl;

    // رفع الصورة إذا كانت موجودة
    if (screenshot != null) {
      final fileName = 'feedback_${feedback.userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = storage.ref().child('feedback_screenshots/$fileName');
      
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': feedback.userId,
          'userName': feedback.userName,
          'type': feedback.type.value,
        },
      );

      final uploadTask = await ref.putFile(screenshot, metadata);
      screenshotUrl = await uploadTask.ref.getDownloadURL();
    }

    // إنشاء المقترح مع رابط الصورة
    final feedbackData = feedback.toJson();
    if (screenshotUrl != null) {
      feedbackData['screenshotUrl'] = screenshotUrl;
    }

    await firestore.collection('feedbacks').add(feedbackData);
  }

  @override
  Future<List<FeedbackModel>> getUserFeedbacks(String userId) async {
    final snapshot = await firestore
        .collection('feedbacks')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => FeedbackModel.fromJson(doc.data(), doc.id))
        .toList();
  }

  @override
  Future<FeedbackModel> getFeedbackById(String feedbackId) async {
    final doc = await firestore.collection('feedbacks').doc(feedbackId).get();

    if (!doc.exists) {
      throw Exception('Feedback not found');
    }

    return FeedbackModel.fromJson(doc.data()!, doc.id);
  }

  @override
  Future<List<FeedbackModel>> getAllFeedbacks() async {
    final snapshot = await firestore
        .collection('feedbacks')
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => FeedbackModel.fromJson(doc.data(), doc.id))
        .toList();
  }

  @override
  Future<void> updateFeedbackStatus({
    required String feedbackId,
    required FeedbackStatus status,
    String? adminResponse,
  }) async {
    final updateData = <String, dynamic>{
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (adminResponse != null && adminResponse.isNotEmpty) {
      updateData['adminResponse'] = adminResponse;
    }

    await firestore.collection('feedbacks').doc(feedbackId).update(updateData);
  }

  @override
  Future<void> deleteFeedback(String feedbackId) async {
    await firestore.collection('feedbacks').doc(feedbackId).delete();
  }
}
