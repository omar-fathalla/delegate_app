import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

abstract class PenaltyRemoteDataSource {
  Future<void> createPenalty(PenaltyModel penalty);
  Future<List<PenaltyModel>> getCompanyPenalties(String companyId);
  Future<List<PenaltyModel>> getAllPenalties();
  Future<void> updatePenaltyStatus({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  });
  Future<void> deletePenalty(String penaltyId);
  Future<EvidenceFile> uploadEvidenceFile({
    required File file,
    required String penaltyId,
  });
}

class PenaltyRemoteDataSourceImpl implements PenaltyRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  PenaltyRemoteDataSourceImpl({
    required this.firestore,
    required this.storage,
  });

  CollectionReference<Map<String, dynamic>> get _penaltiesRef =>
      firestore.collection('penalties');

  @override
  Future<void> createPenalty(PenaltyModel penalty) async {
    try {
      final docRef = _penaltiesRef.doc(
        penalty.penaltyId.isNotEmpty ? penalty.penaltyId : null,
      );
      final finalPenalty = PenaltyModel(
        penaltyId: docRef.id,
        companyId: penalty.companyId,
        companyName: penalty.companyName,
        branchId: penalty.branchId,
        branchName: penalty.branchName,
        createdById: penalty.createdById,
        createdByName: penalty.createdByName,
        title: penalty.title,
        category: penalty.category,
        incidentDescription: penalty.incidentDescription,
        fineAmount: penalty.fineAmount,
        currency: penalty.currency,
        status: penalty.status,
        evidenceFiles: penalty.evidenceFiles,
        targetDelegateId: penalty.targetDelegateId,
        targetDelegateName: penalty.targetDelegateName,
        isRepeated: penalty.isRepeated,
        createdAt: penalty.createdAt,
        updatedAt: penalty.updatedAt,
      );

      await docRef.set(finalPenalty.toJson());

      // Send notifications to Area Marketing Manager & General Manager
      try {
        final notifBody =
            'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ ${finalPenalty.fineAmount.toStringAsFixed(0)} ج.م على شركة (${finalPenalty.companyName}) بفرع (${finalPenalty.branchName ?? "الفرع"}).';

        // 1. Role-based notifications
        for (final roleKey in ['branchesMarketingManager', 'organizationAdmin', 'super-admin']) {
          await firestore.collection('notifications').add({
            'title': '🚨 تسجيل مخالفة جديدة قيد المراجعة',
            'body': notifBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'branchId': finalPenalty.branchId,
            'delegateUid': roleKey,
            'read': false,
            'createdAt': Timestamp.now(),
          });
        }

        // 2. Specific manager accounts in Firestore
        final usersSnap = await firestore
            .collection('users')
            .where('role', whereIn: [
              'branchesMarketingManager',
              'organizationAdmin',
              'superAdmin',
              'branches_marketing'
            ])
            .get();

        for (final userDoc in usersSnap.docs) {
          final uid = userDoc.id;
          final phone = userDoc.data()['phoneNumber']?.toString();
          await firestore.collection('notifications').add({
            'title': '🚨 تسجيل مخالفة جديدة قيد المراجعة',
            'body': notifBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'branchId': finalPenalty.branchId,
            'delegateUid': uid,
            if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
            'read': false,
            'createdAt': Timestamp.now(),
          });
        }
      } catch (_) {
        // Notification failure should not block penalty creation
      }
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في تسجيل الغرامة.');
    } catch (e) {
      throw ServerException('حدث خطأ غير متوقع أثناء تسجيل الغرامة.');
    }
  }

  @override
  Future<List<PenaltyModel>> getCompanyPenalties(String companyId) async {
    try {
      final snapshot = await _penaltiesRef
          .where('companyId', isEqualTo: companyId)
          .get();

      final list = snapshot.docs
          .map((doc) => PenaltyModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في جلب قائمة المخالفات.');
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<PenaltyModel>> getAllPenalties() async {
    try {
      final snapshot = await _penaltiesRef.get();
      final list = snapshot.docs
          .map((doc) => PenaltyModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في جلب كافة المخالفات.');
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> updatePenaltyStatus({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status.toFirestoreString(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (rejectionReason != null && rejectionReason.isNotEmpty) {
        updateData['rejectionReason'] = rejectionReason;
      }

      if (status == PenaltyStatus.pendingGeneralManager && reviewerName != null) {
        updateData['branchesMarketingApprovedBy'] = reviewerName;
        updateData['branchesMarketingApprovedAt'] = Timestamp.fromDate(DateTime.now());
      } else if (status == PenaltyStatus.issued && reviewerName != null) {
        updateData['generalManagerApprovedBy'] = reviewerName;
        updateData['generalManagerApprovedAt'] = Timestamp.fromDate(DateTime.now());
      }

      await _penaltiesRef.doc(penaltyId).update(updateData);
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في تحديث حالة المخالفة.');
    }
  }

  @override
  Future<void> deletePenalty(String penaltyId) async {
    try {
      await _penaltiesRef.doc(penaltyId).delete();
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في حذف المخالفة.');
    } catch (_) {
      throw ServerException('حدث خطأ غير متوقع أثناء حذف المخالفة.');
    }
  }

  @override
  Future<EvidenceFile> uploadEvidenceFile({
    required File file,
    required String penaltyId,
  }) async {
    try {
      final fileName = file.path.split('/').last.split('\\').last;
      final ext = fileName.split('.').last.toLowerCase();
      final fileType = (ext == 'pdf')
          ? 'PDF'
          : (ext == 'doc' || ext == 'docx')
              ? 'DOC'
              : 'IMAGE';

      final ref = storage
          .ref()
          .child('penalties')
          .child('evidence')
          .child(penaltyId.isNotEmpty ? penaltyId : 'temp')
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      return EvidenceFile(
        fileUrl: downloadUrl,
        fileType: fileType,
        fileName: fileName,
      );
    } catch (e) {
      throw ServerException('فشل في رفع المستند/الصورة المرفقة.');
    }
  }
}
