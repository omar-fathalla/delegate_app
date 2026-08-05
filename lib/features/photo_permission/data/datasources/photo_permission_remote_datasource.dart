import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import '../models/photo_permission_model.dart';
import '../models/captured_photo_model.dart';

abstract class PhotoPermissionRemoteDataSource {
  Future<PhotoPermissionModel> requestPermission({
    required String organizationUID,
    required String companyUID,
    required String companyName,
    int? companyCode,
    required List<String> branchIds,
    required List<String> branchNames,
    required DateTime startDate,
    required DateTime endDate,
    required String requestedBy,
  });

  Future<PhotoPermissionModel> approvePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String status,
    required String approvedBy,
  });

  Future<PhotoPermissionModel> togglePermissionBySupervisor({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required bool isEnabled,
  });

  Future<List<PhotoPermissionModel>> getPermissions({
    required String organizationUID,
    required String companyUID,
  });

  Future<List<PhotoPermissionModel>> getOngoingPermissions({
    required String organizationUID,
  });

  Future<CapturedPhotoModel> uploadPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String branchId,
    required String branchName,
    required String delegateUID,
    required String delegateName,
    required File imageFile,
    required String comment,
    required double latitude,
    required double longitude,
  });

  Future<List<CapturedPhotoModel>> getCapturedPhotos({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  });

  Future<List<CapturedPhotoModel>> getDelegateCapturedPhotos({
    required String delegateUID,
  });

  Future<List<CapturedPhotoModel>> getCompanyCapturedPhotos({
    required String companyUID,
    String? organizationUID,
  });

  Future<void> deleteCapturedPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String photoId,
    required String photoUrl,
  });
}

class PhotoPermissionRemoteDataSourceImpl implements PhotoPermissionRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  PhotoPermissionRemoteDataSourceImpl({
    required this.firestore,
    required this.storage,
  });

  Future<void> _ensureAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    } else {
      try {
        await auth.currentUser!.getIdToken(true);
      } catch (_) {
        if (auth.currentUser?.isAnonymous == true) {
          await auth.signOut();
          await auth.signInAnonymously();
        }
      }
    }
  }

  @override
  Future<PhotoPermissionModel> requestPermission({
    required String organizationUID,
    required String companyUID,
    required String companyName,
    int? companyCode,
    required List<String> branchIds,
    required List<String> branchNames,
    required DateTime startDate,
    required DateTime endDate,
    required String requestedBy,
  }) async {
    try {
      await _ensureAuth();

      // التحقق من عدم وجود إذن فعال أو معلق قيد المراجعة لنفس الشركة
      final existingDocs = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .get();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final hasActiveOrPending = existingDocs.docs.any((doc) {
        final perm = PhotoPermissionModel.fromFirestore(doc);
        final status = perm.status.toLowerCase();
        final isPending = status == 'pending';
        final isActive = status == 'approved' && !perm.endDate.isBefore(todayStart);
        return isPending || isActive;
      });

      if (hasActiveOrPending) {
        throw 'يوجد بالفعل إذن تصوير فعال أو قيد المراجعة لهذه الشركة. لا يمكن إرسال طلب جديد حتى انتهاء الإذن الحالي.';
      }

      final docRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc();

      final model = PhotoPermissionModel(
        uid: docRef.id,
        organizationUID: organizationUID,
        companyUID: companyUID,
        companyName: companyName,
        companyCode: companyCode,
        branchIds: branchIds,
        branchNames: branchNames,
        startDate: startDate,
        endDate: endDate,
        status: 'pending',
        requestedBy: requestedBy,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isSupervisorEnabled: true,
      );

      await docRef.set(model.toFirestore());
      return model;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إنشاء طلب إذن التصوير.');
    }
  }

  @override
  Future<PhotoPermissionModel> approvePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String status,
    required String approvedBy,
  }) async {
    try {
      await _ensureAuth();
      final docRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId);

      await docRef.update({
        'status': status,
        'approvedBy': approvedBy,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final doc = await docRef.get();
      return PhotoPermissionModel.fromFirestore(doc);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في مراجعة إذن التصوير.');
    }
  }

  @override
  Future<PhotoPermissionModel> togglePermissionBySupervisor({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required bool isEnabled,
  }) async {
    try {
      await _ensureAuth();
      final docRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId);

      await docRef.update({
        'isSupervisorEnabled': isEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final doc = await docRef.get();
      return PhotoPermissionModel.fromFirestore(doc);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تعديل حالة إذن التصوير من قبل المشرف.');
    }
  }

  @override
  Future<List<PhotoPermissionModel>> getPermissions({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      await _ensureAuth();
      if (companyUID.isEmpty) {
        // Marketing user fetching for all companies across organizations
        final snapshot = await firestore
            .collectionGroup('photo_permissions')
            .get();

        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        
        // Sort in memory by createdAt descending
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      } else {
        // Supervisor fetching for their specific company
        final snapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('photo_permissions')
            .get();

        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب طلبات إذن التصوير.');
    }
  }

  @override
  Future<List<PhotoPermissionModel>> getOngoingPermissions({
    required String organizationUID,
  }) async {
    try {
      await _ensureAuth();
      final snapshot = await firestore
          .collectionGroup('photo_permissions')
          .get();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      // التصفية محلياً في الذاكرة لجميع الأذونات الفعالة اليوم
      return snapshot.docs
          .map((doc) => PhotoPermissionModel.fromFirestore(doc))
          .where((permission) =>
              permission.status.toLowerCase() == 'approved' &&
              permission.isSupervisorEnabled != false &&
              !permission.startDate.isAfter(todayEnd) &&
              !permission.endDate.isBefore(todayStart))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب الأذونات الجارية حالياً.');
    }
  }

  @override
  Future<CapturedPhotoModel> uploadPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String branchId,
    required String branchName,
    required String delegateUID,
    required String delegateName,
    required File imageFile,
    required String comment,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _ensureAuth();
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = storage.ref().child(
          'organizations/$organizationUID/companies/$companyUID/permissions/$permissionId/$fileName');

      await ref.putFile(imageFile);
      final photoUrl = await ref.getDownloadURL();

      final docRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId)
          .collection('captured_photos')
          .doc();

      final model = CapturedPhotoModel(
        uid: docRef.id,
        permissionId: permissionId,
        organizationUID: organizationUID,
        companyUID: companyUID,
        branchId: branchId,
        branchName: branchName,
        delegateUID: delegateUID,
        delegateName: delegateName,
        photoUrl: photoUrl,
        comment: comment,
        latitude: latitude,
        longitude: longitude,
        capturedAt: DateTime.now(),
      );

      await docRef.set(model.toFirestore());
      return model;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في رفع الصورة وتسجيلها في النظام.');
    }
  }

  @override
  Future<List<CapturedPhotoModel>> getCapturedPhotos({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  }) async {
    try {
      await _ensureAuth();
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId)
          .collection('captured_photos')
          .orderBy('capturedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CapturedPhotoModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب الصور المسجلة للإذن.');
    }
  }

  @override
  Future<List<CapturedPhotoModel>> getDelegateCapturedPhotos({
    required String delegateUID,
  }) async {
    try {
      await _ensureAuth();
      final snapshot = await firestore
          .collectionGroup('captured_photos')
          .where('delegateUID', isEqualTo: delegateUID)
          .orderBy('capturedAt', descending: true)
          .get();

      final docs = snapshot.docs
          .map((doc) => CapturedPhotoModel.fromFirestore(doc))
          .toList();

      return docs;
    } on FirebaseException catch (e) {
      debugPrint('Firestore Error in getDelegateCapturedPhotos: $e');
      throw ServerFailure('فشل في جلب تقرير صور المندوب: [${e.code}] ${e.message}');
    } catch (e) {
      debugPrint('Unexpected Error in getDelegateCapturedPhotos: $e');
      throw ServerFailure('حدث خطأ غير متوقع: $e');
    }
  }

  @override
  Future<List<CapturedPhotoModel>> getCompanyCapturedPhotos({
    required String companyUID,
    String? organizationUID,
  }) async {
    try {
      await _ensureAuth();
      final snapshot = await firestore
          .collectionGroup('captured_photos')
          .where('companyUID', isEqualTo: companyUID)
          .orderBy('capturedAt', descending: true)
          .get();

      final docs = snapshot.docs
          .map((doc) => CapturedPhotoModel.fromFirestore(doc))
          .toList();

      return docs;
    } on FirebaseException catch (e) {
      debugPrint('Firestore Error in getCompanyCapturedPhotos: $e');
      throw ServerFailure('فشل في جلب صور الشركة: [${e.code}] ${e.message}');
    } catch (e) {
      debugPrint('Unexpected Error in getCompanyCapturedPhotos: $e');
      throw ServerFailure('حدث خطأ غير متوقع: $e');
    }
  }

  @override
  Future<void> deleteCapturedPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String photoId,
    required String photoUrl,
  }) async {
    try {
      await _ensureAuth();
      final snapshot = await firestore
          .collectionGroup('captured_photos')
          .where('photoId', isEqualTo: photoId)
          .get();
          
      for (var doc in snapshot.docs) {
        try {
          final imageUrl = doc.data()['imageUrl'] as String?;
          if (imageUrl != null) {
            final ref = storage.refFromURL(imageUrl);
            await ref.delete();
          }
        } catch (e) {
          debugPrint('Error deleting image from storage: $e');
        }
        await doc.reference.delete();
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore Error in deleteCapturedPhoto: $e');
      throw ServerFailure('فشل في حذف الصورة: [${e.code}] ${e.message}');
    } catch (e) {
      debugPrint('Unexpected Error in deleteCapturedPhoto: $e');
      throw ServerFailure('حدث خطأ غير متوقع: $e');
    }
  }
}
