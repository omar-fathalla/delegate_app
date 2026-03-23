import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/changelog/data/models/app_update_model.dart';

/// Remote data source for fetching app updates from Firestore.
abstract class ChangelogRemoteDataSource {
  /// Fetches all active updates, ordered by creation date (newest first).
  Future<List<AppUpdateModel>> getUpdates();

  /// Fetches updates created after [since].
  Future<List<AppUpdateModel>> getUpdatesSince(DateTime since);
}

class ChangelogRemoteDataSourceImpl implements ChangelogRemoteDataSource {
  final FirebaseFirestore firestore;

  ChangelogRemoteDataSourceImpl({required this.firestore});

  @override
  Future<List<AppUpdateModel>> getUpdates() async {
    try {
      final snapshot = await firestore
          .collection('app_updates')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.docs
          .map((doc) => AppUpdateModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw ServerFailure('حدث خطأ أثناء جلب التحديثات: ${e.toString()}');
    }
  }

  @override
  Future<List<AppUpdateModel>> getUpdatesSince(DateTime since) async {
    try {
      final snapshot = await firestore
          .collection('app_updates')
          .where('isActive', isEqualTo: true)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.docs
          .map((doc) => AppUpdateModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw ServerFailure('حدث خطأ أثناء جلب التحديثات الجديدة: ${e.toString()}');
    }
  }
}
