import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart' show UserRole;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
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
    String? department,
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

  Stream<List<PhotoPermissionModel>> streamPermissions({
    required String organizationUID,
    required String companyUID,
  });

  Future<List<PhotoPermissionModel>> getOngoingPermissions({
    required String organizationUID,
  });

  Future<void> updatePermissionBranches({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required List<String> branchIds,
    required List<String> branchNames,
  });

  Future<void> updatePermissionDates({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required DateTime startDate,
    required DateTime endDate,
  });

  Future<void> deletePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  });

  Future<CapturedPhotoModel> uploadPhoto({
    required String organizationUID,
    required String companyUID,
    String companyName = '',
    int? companyCode,
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
    String? branchName,
    int? limit,
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
    String? department,
  }) async {
    try {
      // Company is the tenant: check every chain so a nested-path list
      // (historically over the 1000-expression budget) cannot hide an
      // active or pending permission on another chain.
      final existingDocs = await firestore
          .collectionGroup('photo_permissions')
          .where('companyUID', isEqualTo: companyUID)
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
        department: department,
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
  Stream<List<PhotoPermissionModel>> streamPermissions({
    required String organizationUID,
    required String companyUID,
  }) {
    if (companyUID.isEmpty && organizationUID.isEmpty) {
      return firestore
          .collectionGroup('photo_permissions')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      });
    } else if (companyUID.isEmpty) {
      return firestore
          .collectionGroup('photo_permissions')
          .where('organizationUID', isEqualTo: organizationUID)
          .snapshots(includeMetadataChanges: true)
          .handleError((Object e, StackTrace st) {
            Error.throwWithStackTrace(e, st);
          })
          .map((snapshot) {
        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      });
    } else {
      // Company is the tenant: list every chain of this company. The nested
      // path historically exceeded the 1000-expression list budget.
      return firestore
          .collectionGroup('photo_permissions')
          .where('companyUID', isEqualTo: companyUID)
          .snapshots(includeMetadataChanges: true)
          .handleError((Object e, StackTrace st) {
            Error.throwWithStackTrace(e, st);
          })
          .map((snapshot) {
        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      });
    }
  }

  @override
  Future<List<PhotoPermissionModel>> getPermissions({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      if (companyUID.isEmpty && organizationUID.isEmpty) {
        // Global staff: latest 100 across every organization.
        final snapshot = await firestore
            .collectionGroup('photo_permissions')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .getResilient();

        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      } else if (companyUID.isEmpty) {
        // Marketing / org-admin: constrain to their organization so the
        // collection-group query is authorized (N-2 spinner).
        final snapshot = await firestore
            .collectionGroup('photo_permissions')
            .where('organizationUID', isEqualTo: organizationUID)
            .getResilient();

        final docs = snapshot.docs
            .map((doc) => PhotoPermissionModel.fromFirestore(doc))
            .toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      } else {
        // Supervisor fetching for their company across every chain.
        final snapshot = await firestore
            .collectionGroup('photo_permissions')
            .where('companyUID', isEqualTo: companyUID)
            .getResilient();

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
      Query query = firestore.collectionGroup('photo_permissions');
          
      if (organizationUID.isNotEmpty) {
        query = query.where('organizationUID', isEqualTo: organizationUID);
      }

      final snapshot = await query.getResilient();

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
    String companyName = '',
    int? companyCode,
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
      final fileName = 'photo_${delegateUID}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = storage.ref().child(
          'organizations/$organizationUID/companies/$companyUID/permissions/$permissionId/$fileName');

      await ref.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'userId': delegateUID,
            'delegateUid': delegateUID,
          },
        ),
      );
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
        companyName: companyName,
        companyCode: companyCode,
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
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId)
          .collection('captured_photos')
          // TAS-73: the rules decide a captured_photos list only through the
          // collection-group rule, which must prove the tenant from the
          // query. Company + organization equality covers company staff,
          // org-scoped staff and delegates; sort on the client so no
          // composite index is needed.
          .where('companyUID', isEqualTo: companyUID)
          .where('organizationUID', isEqualTo: organizationUID)
          .getResilient(timeout: const Duration(seconds: 6));

      final photos = snapshot.docs
          .map((doc) => CapturedPhotoModel.fromFirestore(doc))
          .toList();
      photos.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      return photos;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب الصور المسجلة للإذن.');
    } catch (e) {
      debugPrint('Error fetching captured photos: $e');
      throw const ServerFailure('فشل في جلب الصور المسجلة للإذن.');
    }
  }

  @override
  Future<List<CapturedPhotoModel>> getDelegateCapturedPhotos({
    required String delegateUID,
  }) async {
    try {
      // TAS-73: no unfiltered collection-group fallback; the rules deny it.
      // delegateUID equality has its own collection-group single-field index.
      final snapshot = await firestore
          .collectionGroup('captured_photos')
          .where('delegateUID', isEqualTo: delegateUID)
          .getResilient();

      final docs = snapshot.docs
          .map((doc) => CapturedPhotoModel.fromFirestore(doc))
          .toList();

      docs.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
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
    String? branchName,
    int? limit,
  }) async {
    try {
      try {
        // TAS-73: company staff by company, org-scoped staff by organization,
        // global staff unfiltered (latest 200).
        Query query = capturedPhotosTenantQuery(
          firestore,
          companyUID: companyUID,
          organizationUID: organizationUID ?? '',
        );
        if (branchName != null && branchName.trim().isNotEmpty && branchName != 'all') {
          query = query.where('branchName', isEqualTo: branchName.trim());
        }
        final effectiveLimit = (limit != null && limit > 0)
            ? limit
            : (companyUID.isEmpty && (organizationUID ?? '').isEmpty ? 200 : null);
        if (effectiveLimit != null) {
          query = query.limit(effectiveLimit);
        }
        final snapshot = await query.getResilient();

        final docs = snapshot.docs
            .map((doc) => CapturedPhotoModel.fromFirestore(doc))
            .toList();

        docs.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
        return docs;
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          debugPrint(
            'Company captured photos index missing/building, fetching collectionGroup with limit and filtering locally in Dart',
          );
          // Same tenant filter as above (an unfiltered list is denied);
          // only the branch filter moves to the client.
          Query fallbackQuery = capturedPhotosTenantQuery(
            firestore,
            companyUID: companyUID,
            organizationUID: organizationUID ?? '',
          );
          if (limit != null && limit > 0) {
            fallbackQuery = fallbackQuery.limit(limit * 3);
          }
          final snapshot = await fallbackQuery.get();
          final docs = snapshot.docs
              .map((doc) => CapturedPhotoModel.fromFirestore(doc))
              .where(
                (photo) =>
                    (companyUID.isEmpty || photo.companyUID == companyUID) &&
                    (branchName == null || branchName.isEmpty || branchName == 'all' || photo.branchName.trim() == branchName.trim()),
              )
              .toList();
          docs.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
          if (limit != null && limit > 0 && docs.length > limit) {
            return docs.sublist(0, limit);
          }
          return docs;
        }
        rethrow;
      }
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
      // 1. Delete image from Storage if URL is available
      if (photoUrl.isNotEmpty) {
        try {
          final ref = storage.refFromURL(photoUrl);
          await ref.delete();
        } catch (e) {
          debugPrint('Error deleting image from storage using photoUrl: $e');
        }
      }

      // 2. Direct document deletion if path IDs are present
      bool deletedDirectly = false;
      if (organizationUID.isNotEmpty &&
          companyUID.isNotEmpty &&
          permissionId.isNotEmpty &&
          photoId.isNotEmpty) {
        try {
          final directDocRef = firestore
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .collection('photo_permissions')
              .doc(permissionId)
              .collection('captured_photos')
              .doc(photoId);

          final directDoc = await directDocRef.get();
          if (directDoc.exists) {
            final storedUrl = directDoc.data()?['photoUrl'] as String?;
            if (photoUrl.isEmpty && storedUrl != null && storedUrl.isNotEmpty) {
              try {
                final ref = storage.refFromURL(storedUrl);
                await ref.delete();
              } catch (_) {}
            }
            await directDocRef.delete();
            deletedDirectly = true;
          }
        } catch (e) {
          debugPrint('Direct doc deletion attempt: $e');
        }
      }

      // 3. Fallback: Search across collectionGroup if not deleted directly
      if (!deletedDirectly && photoId.isNotEmpty) {
        final snapshot = await firestore
            .collectionGroup('captured_photos')
            .where(FieldPath.documentId, isEqualTo: photoId)
            .get();

        for (var doc in snapshot.docs) {
          try {
            final storedUrl = (doc.data()['photoUrl'] ?? doc.data()['imageUrl']) as String?;
            if (storedUrl != null && storedUrl.isNotEmpty) {
              final ref = storage.refFromURL(storedUrl);
              await ref.delete();
            }
          } catch (e) {
            debugPrint('Error deleting image from storage: $e');
          }
          await doc.reference.delete();
        }

        // Also check if stored by uid field
        if (snapshot.docs.isEmpty) {
          final uidSnapshot = await firestore
              .collectionGroup('captured_photos')
              .where('uid', isEqualTo: photoId)
              .get();

          for (var doc in uidSnapshot.docs) {
            try {
              final storedUrl = (doc.data()['photoUrl'] ?? doc.data()['imageUrl']) as String?;
              if (storedUrl != null && storedUrl.isNotEmpty) {
                final ref = storage.refFromURL(storedUrl);
                await ref.delete();
              }
            } catch (_) {}
            await doc.reference.delete();
          }
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore Error in deleteCapturedPhoto: $e');
      throw ServerFailure('فشل في حذف الصورة: [${e.code}] ${e.message}');
    } catch (e) {
      debugPrint('Unexpected Error in deleteCapturedPhoto: $e');
      throw ServerFailure('حدث خطأ غير متوقع: $e');
    }
  }

  @override
  Future<void> deletePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  }) async {
    try {
      // 1. Delete all captured photos under this permission from Storage and Firestore
      QuerySnapshot<Map<String, dynamic>> photosSnapshot;
      if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
        photosSnapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('photo_permissions')
            .doc(permissionId)
            .collection('captured_photos')
            .get();
      } else {
        photosSnapshot = await firestore
            .collectionGroup('captured_photos')
            .where('permissionId', isEqualTo: permissionId)
            .get();
      }

      for (var doc in photosSnapshot.docs) {
        try {
          final imageUrl = doc.data()['photoUrl'] as String?;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            final ref = storage.refFromURL(imageUrl);
            await ref.delete();
          }
        } catch (e) {
          debugPrint('Error deleting photo image from storage during permission deletion: $e');
        }
        await doc.reference.delete();
      }

      // 2. Delete the permission document
      if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
        await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('photo_permissions')
            .doc(permissionId)
            .delete();
      } else {
        final permSnapshot = await firestore
            .collectionGroup('photo_permissions')
            .where(FieldPath.documentId, isEqualTo: permissionId)
            .get();
        for (var doc in permSnapshot.docs) {
          await doc.reference.delete();
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore Error in deletePermission: $e');
      throwFirestoreFailure(e, 'فشل في حذف إذن التصوير.');
    } catch (e) {
      debugPrint('Unexpected Error in deletePermission: $e');
      throw ServerFailure('حدث خطأ غير متوقع أثناء حذف إذن التصوير: $e');
    }
  }

  @override
  Future<void> updatePermissionBranches({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required List<String> branchIds,
    required List<String> branchNames,
  }) async {
    try {
      final docRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('photo_permissions')
          .doc(permissionId);

      await docRef.update({
        'branchIds': branchIds,
        'branchNames': branchNames,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تعديل فروع إذن التصوير.');
    } catch (e) {
      debugPrint('Unexpected Error in updatePermissionBranches: $e');
      throw ServerFailure('حدث خطأ غير متوقع أثناء التعديل: $e');
    }
  }

  @override
  Future<void> updatePermissionDates({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
        final docRef = firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('photo_permissions')
            .doc(permissionId);

        await docRef.update({
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Fallback search in collectionGroup if org/company was missing
      final q = await firestore
          .collectionGroup('photo_permissions')
          .where(FieldPath.documentId, isEqualTo: permissionId)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        await q.docs.first.reference.update({
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تعديل تاريخ صلاحية إذن التصوير.');
    } catch (e) {
      debugPrint('Unexpected Error in updatePermissionDates: $e');
      throw ServerFailure('حدث خطأ غير متوقع أثناء تعديل التاريخ: $e');
    }
  }
}

/// TAS-73: the tenant filter a `captured_photos` collection-group list needs
/// so the rules can prove access from the query. Company staff filter by
/// company, org-scoped staff (no companyUID) by organization; only global
/// staff (neither) list unfiltered.
Query capturedPhotosTenantQuery(
  FirebaseFirestore firestore, {
  required String companyUID,
  required String organizationUID,
}) {
  return _tenantQuery(
    firestore.collectionGroup('captured_photos'),
    companyUID: companyUID,
    organizationUID: organizationUID,
  );
}

/// TAS-73: same as [capturedPhotosTenantQuery] for `photo_permissions`.
Query<Map<String, dynamic>> photoPermissionsTenantQuery(
  FirebaseFirestore firestore, {
  required String companyUID,
  required String organizationUID,
}) {
  return _tenantQuery(
    firestore.collectionGroup('photo_permissions'),
    companyUID: companyUID,
    organizationUID: organizationUID,
  );
}

Query<Map<String, dynamic>> _tenantQuery(
  Query<Map<String, dynamic>> query, {
  required String companyUID,
  required String organizationUID,
}) {
  final company = companyUID.trim();
  final org = organizationUID.trim();
  if (company.isNotEmpty) return query.where('companyUID', isEqualTo: company);
  if (org.isNotEmpty) return query.where('organizationUID', isEqualTo: org);
  return query;
}

/// TAS-73: the organization to filter photo lists by. Global staff (super
/// admin, technical support) list across organizations; everyone else is
/// held to their own organization.
String photoListOrgScope(UserRole role, String organizationUID) {
  if (role == UserRole.superAdmin || role == UserRole.technicalSupport) {
    return '';
  }
  return organizationUID;
}
