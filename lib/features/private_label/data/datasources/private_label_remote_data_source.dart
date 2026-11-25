import 'package:delegate_app/core/storage/storage_media.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_audit_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_day_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_product_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

abstract class PrivateLabelRemoteDataSource {
  Future<List<PrivateLabelDayModel>> getMonthDays({
    required String organizationUID,
    required String delegateUid,
    required String monthKey,
  });

  Future<List<PrivateLabelDayModel>> getOrganizationMonthDays({
    required String organizationUID,
    required String monthKey,
    String? companyUID,
  });

  /// Reads `privateLabelMonthlyRestDays` from the organization doc.
  Future<int> getRestAllowance(String organizationUID);

  /// Uploads both photos and writes the audit + day summary atomically.
  /// Idempotent: re-syncing an already-written audit is a no-op.
  Future<void> syncAudit(PrivateLabelAuditDraft draft);

  Future<PrivateLabelDayModel> registerRestDay({
    required String organizationUID,
    required String companyUID,
    required String delegateUid,
    required String delegateName,
    required String date,
    required int restAllowance,
  });

  Future<void> cancelRestDay({
    required String organizationUID,
    required String delegateUid,
    required String date,
  });

  Future<List<PrivateLabelAuditModel>> getAudits({
    required String organizationUID,
    String? date,
    String? delegateUid,
    String? companyUID,
  });

  Future<PrivateLabelAuditModel> reviewAudit({
    required String organizationUID,
    required String auditId,
    required PrivateLabelReviewStatus status,
    required String reviewerUid,
    required String reviewerName,
    String? notes,
  });

  Future<List<PrivateLabelProductModel>> getProducts(String organizationUID);

  Future<void> deleteAudit({
    required String organizationUID,
    required String auditId,
    required String delegateUid,
    required String date,
  });

  Future<PrivateLabelAuditModel> updateAudit({
    required String organizationUID,
    required String auditId,
    required String productName,
    String? productId,
    double? referencePrice,
    required double shelfPrice,
    required PrivateLabelStockStatus stockStatus,
    String? barcode,
    String? notes,
  });

  Future<PrivateLabelProductModel> saveProduct(PrivateLabelProductModel product);

  Future<List<String>> getBranches(String organizationUID);
}

class PrivateLabelRemoteDataSourceImpl implements PrivateLabelRemoteDataSource {
  static const int defaultMonthlyRestDays = 4;
  static const String restAllowanceField = 'privateLabelMonthlyRestDays';
  static const String defaultOrganizationUID = 'PiioBFgxaHAeuRdjlDgj';
  static const Duration _timeout = Duration(seconds: 25);

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  PrivateLabelRemoteDataSourceImpl({required this.firestore, required this.storage});

  String _resolveOrg(String org) =>
      org.trim().isNotEmpty ? org.trim() : defaultOrganizationUID;

  DocumentReference<Map<String, dynamic>> _org(String org) =>
      firestore.collection('organizations').doc(_resolveOrg(org));

  CollectionReference<Map<String, dynamic>> _audits(String org) =>
      _org(org).collection('private_label_audits');

  CollectionReference<Map<String, dynamic>> _days(String org) =>
      _org(org).collection('private_label_days');

  CollectionReference<Map<String, dynamic>> _products(String org) =>
      _org(org).collection('private_label_products');

  void _requireOrg(String org) {
    // Empty organizationUID falls back to defaultOrganizationUID via _resolveOrg.
  }

  // ─────────────────────────── Month / KPI ───────────────────────────

  @override
  Future<List<PrivateLabelDayModel>> getMonthDays({
    required String organizationUID,
    required String delegateUid,
    required String monthKey,
  }) async {
    _requireOrg(organizationUID);
    try {
      // Two equality filters → served by single-field index merging (no composite index).
      final snap = await _days(organizationUID)
          .where('delegateUid', isEqualTo: delegateUid)
          .where('month', isEqualTo: monthKey)
          .get()
          .timeout(_timeout);
      return snap.docs
          .map((d) => PrivateLabelDayModel.fromJson(d.data(), d.id))
          // Defensive post-filter (dual-layer scoping).
          .where((d) => d.delegateUid == delegateUid && d.month == monthKey)
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل أيام الشهر.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<List<PrivateLabelDayModel>> getOrganizationMonthDays({
    required String organizationUID,
    required String monthKey,
    String? companyUID,
  }) async {
    _requireOrg(organizationUID);
    try {
      final snap = await _days(organizationUID)
          .where('month', isEqualTo: monthKey)
          .get()
          .timeout(_timeout);
      return snap.docs
          .map((d) => PrivateLabelDayModel.fromJson(d.data(), d.id))
          .where((d) =>
              d.month == monthKey &&
              (companyUID == null || companyUID.isEmpty || d.companyUID == companyUID))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل أيام الشهر للشركة.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<int> getRestAllowance(String organizationUID) async {
    _requireOrg(organizationUID);
    try {
      final doc = await _org(organizationUID).get().timeout(_timeout);
      final value = doc.data()?[restAllowanceField];
      if (value is num && value >= 0 && value <= 15) return value.toInt();
      return defaultMonthlyRestDays;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل رصيد الإجازات.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  // ─────────────────────────── Audits ───────────────────────────

  /// TAS-42: uploads and returns the object path plus, while old app
  /// versions need it, the download URL.
  Future<({String path, String? legacyUrl})> _uploadPhoto({
    required PrivateLabelAuditDraft draft,
    required String localPath,
    required String kind,
  }) async {
    final bytes = await XFile(localPath).readAsBytes();
    final ref = storage.ref().child(
          'organizations/${draft.organizationUID}/private_label/'
          '${draft.auditMonth}/${draft.id}_$kind.jpg',
        );
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return (path: ref.fullPath, legacyUrl: await LegacyStorageUrls.urlFor(ref));
  }

  @override
  Future<void> syncAudit(PrivateLabelAuditDraft draft) async {
    _requireOrg(draft.organizationUID);
    final auditRef = _audits(draft.organizationUID).doc(draft.id);
    final dayRef = _days(draft.organizationUID).doc(
      PrivateLabelDates.dayDocId(draft.delegateUid, draft.auditDate),
    );

    try {
      final existing = await auditRef.get().timeout(_timeout);
      if (existing.exists) return; // Already synced (idempotent retry).

      final productPhoto = await _uploadPhoto(
        draft: draft,
        localPath: draft.productImagePath,
        kind: 'product',
      );
      final pricePhoto = await _uploadPhoto(
        draft: draft,
        localPath: draft.priceImagePath,
        kind: 'price',
      );

      await firestore.runTransaction((tx) async {
        final auditSnap = await tx.get(auditRef);
        if (auditSnap.exists) return;
        final daySnap = await tx.get(dayRef);

        tx.set(
          auditRef,
          PrivateLabelAuditModel.firestoreFromDraft(
            draft,
            productPhotoPath: productPhoto.path,
            pricePhotoPath: pricePhoto.path,
            productPhotoUrl: productPhoto.legacyUrl,
            pricePhotoUrl: pricePhoto.legacyUrl,
          ),
        );

        if (daySnap.exists) {
          // Uploading on a registered rest day converts it back into a worked
          // day, which automatically returns the rest day to the allowance.
          tx.update(dayRef, {
            'type': PrivateLabelDayType.worked.name,
            'auditsCount': FieldValue.increment(1),
            'branchNames': FieldValue.arrayUnion([draft.branchName]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(dayRef, {
            ...PrivateLabelDayModel(
              id: dayRef.id,
              organizationUID: draft.organizationUID,
              companyUID: draft.companyUID,
              delegateUid: draft.delegateUid,
              delegateName: draft.delegateName,
              date: draft.auditDate,
              month: draft.auditMonth,
              type: PrivateLabelDayType.worked,
              auditsCount: 1,
              branchNames: [draft.branchName],
            ).toJson(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }).timeout(_timeout);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في رفع التوثيق.');
    } on TimeoutException {
      throwTimeoutFailure();
    } catch (e) {
      throw ServerFailure('فشل في رفع التوثيق: $e');
    }
  }

  @override
  Future<List<PrivateLabelAuditModel>> getAudits({
    required String organizationUID,
    String? date,
    String? delegateUid,
    String? companyUID,
  }) async {
    _requireOrg(organizationUID);
    try {
      Query<Map<String, dynamic>> query = _audits(organizationUID);
      if (date != null && date.isNotEmpty) {
        query = query.where('auditDate', isEqualTo: date);
      }
      if (delegateUid != null && delegateUid.isNotEmpty) {
        query = query.where('delegateUid', isEqualTo: delegateUid);
      }
      if (companyUID != null && companyUID.isNotEmpty) {
        query = query.where('companyUID', isEqualTo: companyUID);
      }
      if (date == null || date.isEmpty) {
        query = query.limit(300);
      }
      final snap = await query.get().timeout(_timeout);
      final list = snap.docs
          .map((d) => PrivateLabelAuditModel.fromJson(d.data(), d.id))
          .toList();

      // Dual-layer isolation: in-memory post-filter.
      if (date != null && date.isNotEmpty) {
        list.removeWhere((a) => a.auditDate != date);
      }
      if (delegateUid != null && delegateUid.isNotEmpty) {
        list.removeWhere((a) => a.delegateUid != delegateUid);
      }
      if (companyUID != null && companyUID.isNotEmpty) {
        list.removeWhere((a) => a.companyUID != companyUID);
      }
      list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      return list;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل التوثيقات.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<PrivateLabelAuditModel> reviewAudit({
    required String organizationUID,
    required String auditId,
    required PrivateLabelReviewStatus status,
    required String reviewerUid,
    required String reviewerName,
    String? notes,
  }) async {
    _requireOrg(organizationUID);
    final auditRef = _audits(organizationUID).doc(auditId);
    try {
      final updated = await firestore.runTransaction((tx) async {
        final snap = await tx.get(auditRef);
        if (!snap.exists) {
          throw const ServerFailure('التوثيق ده مش موجود أو اتمسح.');
        }
        final current = PrivateLabelAuditModel.fromJson(snap.data()!, snap.id);
        final dayRef = _days(organizationUID).doc(
          PrivateLabelDates.dayDocId(current.delegateUid, current.auditDate),
        );
        final daySnap = await tx.get(dayRef);

        final wasRejected = current.reviewStatus == PrivateLabelReviewStatus.rejected;
        final isRejected = status == PrivateLabelReviewStatus.rejected;

        tx.update(auditRef, {
          'reviewStatus': status.name,
          'reviewedBy': reviewerUid,
          'reviewedByName': reviewerName,
          'reviewNotes': notes?.trim(),
          'reviewedAt': FieldValue.serverTimestamp(),
        });

        if (daySnap.exists && wasRejected != isRejected) {
          tx.update(dayRef, {
            'rejectedCount': FieldValue.increment(isRejected ? 1 : -1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        return current.copyWith(
          reviewStatus: status,
          reviewedBy: reviewerUid,
          reviewedByName: reviewerName,
          reviewNotes: notes?.trim(),
          reviewedAt: DateTime.now(),
        );
      }).timeout(_timeout);

      return PrivateLabelAuditModel(
        id: updated.id,
        organizationUID: updated.organizationUID,
        companyUID: updated.companyUID,
        delegateUid: updated.delegateUid,
        delegateName: updated.delegateName,
        branchName: updated.branchName,
        productId: updated.productId,
        productName: updated.productName,
        barcode: updated.barcode,
        referencePrice: updated.referencePrice,
        shelfPrice: updated.shelfPrice,
        stockStatus: updated.stockStatus,
        notes: updated.notes,
        productPhotoUrl: updated.productPhotoUrl,
        pricePhotoUrl: updated.pricePhotoUrl,
        reviewStatus: updated.reviewStatus,
        reviewedBy: updated.reviewedBy,
        reviewedByName: updated.reviewedByName,
        reviewNotes: updated.reviewNotes,
        reviewedAt: updated.reviewedAt,
        auditDate: updated.auditDate,
        auditMonth: updated.auditMonth,
        capturedAt: updated.capturedAt,
        syncedAt: updated.syncedAt,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حفظ قرار المراجعة.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<void> deleteAudit({
    required String organizationUID,
    required String auditId,
    required String delegateUid,
    required String date,
  }) async {
    _requireOrg(organizationUID);
    try {
      final auditRef = _audits(organizationUID).doc(auditId);
      final dayRef = _days(organizationUID).doc('${delegateUid}_$date');

      await firestore.runTransaction((tx) async {
        final auditSnap = await tx.get(auditRef);
        if (!auditSnap.exists) return;
        final isRejected = auditSnap.data()?['reviewStatus'] == PrivateLabelReviewStatus.rejected.name;

        tx.delete(auditRef);

        final daySnap = await tx.get(dayRef);
        if (daySnap.exists) {
          final count = (daySnap.data()?['auditsCount'] as num?)?.toInt() ?? 1;
          if (count <= 1) {
            tx.delete(dayRef);
          } else {
            tx.update(dayRef, {
              'auditsCount': FieldValue.increment(-1),
              if (isRejected) 'rejectedCount': FieldValue.increment(-1),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }).timeout(_timeout);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف التوثيق.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<PrivateLabelAuditModel> updateAudit({
    required String organizationUID,
    required String auditId,
    required String productName,
    String? productId,
    double? referencePrice,
    required double shelfPrice,
    required PrivateLabelStockStatus stockStatus,
    String? barcode,
    String? notes,
  }) async {
    _requireOrg(organizationUID);
    try {
      final ref = _audits(organizationUID).doc(auditId);
      final hasMismatch = referencePrice != null &&
          (shelfPrice - referencePrice).abs() > PrivateLabelAudit.priceTolerance;

      await ref.update({
        'productName': productName.trim(),
        'productId': productId,
        'referencePrice': referencePrice,
        'shelfPrice': shelfPrice,
        'priceMismatch': hasMismatch,
        'stockStatus': stockStatus.name,
        'barcode': barcode,
        'notes': notes?.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(_timeout);

      final snap = await ref.get().timeout(_timeout);
      return PrivateLabelAuditModel.fromJson(snap.data()!, snap.id);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تعديل التوثيق.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  // ─────────────────────────── Rest days ───────────────────────────

  @override
  Future<PrivateLabelDayModel> registerRestDay({
    required String organizationUID,
    required String companyUID,
    required String delegateUid,
    required String delegateName,
    required String date,
    required int restAllowance,
  }) async {
    _requireOrg(organizationUID);
    final monthKey = PrivateLabelDates.monthKeyOfDay(date);
    final dayRef = _days(organizationUID).doc(PrivateLabelDates.dayDocId(delegateUid, date));

    try {
      final monthDays = await getMonthDays(
        organizationUID: organizationUID,
        delegateUid: delegateUid,
        monthKey: monthKey,
      );
      final usedRest = monthDays.where((d) => d.isRest && d.date != date).length;
      if (usedRest >= restAllowance) {
        throw ServerFailure('خلّصت رصيد الإجازات للشهر ده ($restAllowance أيام).');
      }

      final model = PrivateLabelDayModel(
        id: dayRef.id,
        organizationUID: organizationUID,
        companyUID: companyUID,
        delegateUid: delegateUid,
        delegateName: delegateName,
        date: date,
        month: monthKey,
        type: PrivateLabelDayType.rest,
      );

      await firestore.runTransaction((tx) async {
        final snap = await tx.get(dayRef);
        if (snap.exists) {
          final existing = PrivateLabelDayModel.fromJson(snap.data()!, snap.id);
          if (existing.isRest) return;
          if (existing.auditsCount > 0) {
            throw const ServerFailure('اليوم ده فيه توثيق بالفعل، فمينفعش يتسجل إجازة.');
          }
        }
        tx.set(dayRef, {
          ...model.toJson(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(_timeout);

      return model;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تسجيل الإجازة.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<void> cancelRestDay({
    required String organizationUID,
    required String delegateUid,
    required String date,
  }) async {
    _requireOrg(organizationUID);
    final dayRef = _days(organizationUID).doc(PrivateLabelDates.dayDocId(delegateUid, date));
    try {
      await firestore.runTransaction((tx) async {
        final snap = await tx.get(dayRef);
        if (!snap.exists) return;
        final existing = PrivateLabelDayModel.fromJson(snap.data()!, snap.id);
        if (!existing.isRest || existing.auditsCount > 0) {
          throw const ServerFailure('اليوم ده مش مسجل كإجازة.');
        }
        tx.delete(dayRef);
      }).timeout(_timeout);
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إلغاء الإجازة.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  // ─────────────────────────── Catalog & branches ───────────────────────────

  @override
  Future<List<PrivateLabelProductModel>> getProducts(String organizationUID) async {
    _requireOrg(organizationUID);
    try {
      final snap = await _products(organizationUID).get().timeout(_timeout);
      final rawDocs = <String, Map<String, dynamic>>{
        for (final d in snap.docs) d.id: d.data(),
      };
      final list = snap.docs
          .map((d) => PrivateLabelProductModel.fromJson(d.data(), d.id))
          // Inactive items are returned too (catalog manager can reactivate them);
          // the marketer's capture sheet filters them out.
          .where((p) => p.name.trim().isNotEmpty)
          .toList();

      await _ensureDefaultCatalogProducts(
        organizationUID: organizationUID,
        list: list,
        rawDocs: rawDocs,
      );

      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل كتالوج المنتجات.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  /// Ensures the 4 core Fathalla Private Label products exist in Firestore with
  /// their default images, prices, and barcodes, without overwriting user edits.
  Future<void> _ensureDefaultCatalogProducts({
    required String organizationUID,
    required List<PrivateLabelProductModel> list,
    required Map<String, Map<String, dynamic>> rawDocs,
  }) async {
    final effectiveOrg = _resolveOrg(organizationUID);
    final defaults = PrivateLabelProduct.defaultCatalog(effectiveOrg);
    for (final seed in defaults) {
      final seedLower = seed.name.trim().toLowerCase();
      final matchIdx = list.indexWhere((p) =>
          p.id == seed.id ||
          (seed.barcode != null && p.barcode == seed.barcode) ||
          p.name.trim().toLowerCase() == seedLower);

      if (matchIdx == -1) {
        final model = PrivateLabelProductModel.fromEntity(seed);
        try {
          await _products(effectiveOrg).doc(seed.id).set({
            ...model.toJson(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
        } catch (_) {}
        list.add(model);
      } else {
        final existing = list[matchIdx];
        final raw = rawDocs[existing.id] ?? const <String, dynamic>{};
        final storedImage =
            (raw['imagePath'] ?? raw['imageUrl'] ?? raw['photoUrl'] ?? '').toString().trim();
        final storedCategory = (raw['category'] ?? '').toString().trim();
        final storedBarcode = (raw['barcode'] ?? '').toString().trim();
        final hasStoredPrice = raw['referencePrice'] != null;

        final needsImage = storedImage.isEmpty && seed.imageUrl != null;
        final needsCategory = storedCategory.isEmpty && seed.category != null;
        final needsBarcode = storedBarcode.isEmpty && seed.barcode != null;
        final needsPrice = !hasStoredPrice && seed.referencePrice != null;

        if (needsImage || needsCategory || needsBarcode || needsPrice) {
          final updated = PrivateLabelProductModel.fromEntity(
            existing.copyWith(
              imageUrl: needsImage ? seed.imageUrl : existing.imageUrl,
              category: needsCategory ? seed.category : existing.category,
              barcode: needsBarcode ? seed.barcode : existing.barcode,
              referencePrice: needsPrice ? seed.referencePrice : existing.referencePrice,
            ),
          );
          list[matchIdx] = updated;
          try {
            await _products(effectiveOrg).doc(existing.id).set({
              if (needsImage) 'imageUrl': seed.imageUrl,
              if (needsCategory) 'category': seed.category,
              if (needsBarcode) 'barcode': seed.barcode,
              if (needsPrice) 'referencePrice': seed.referencePrice,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
          } catch (_) {}
        }
      }
    }
  }

  @override
  Future<PrivateLabelProductModel> saveProduct(PrivateLabelProductModel product) async {
    _requireOrg(product.organizationUID);
    try {
      final ref = product.id.isEmpty
          ? _products(product.organizationUID).doc()
          : _products(product.organizationUID).doc(product.id);

      var finalImageUrl = product.imageUrl?.trim();
      String? legacyImageUrl;
      var uploaded = false;
      if (finalImageUrl != null &&
          finalImageUrl.isNotEmpty &&
          !finalImageUrl.startsWith('http://') &&
          !finalImageUrl.startsWith('https://') &&
          !finalImageUrl.startsWith('assets/')) {
        try {
          final bytes = await XFile(finalImageUrl).readAsBytes();
          final storageRef = storage.ref().child(
                'organizations/${product.organizationUID}/private_label_products/${ref.id}.jpg',
              );
          await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
          // TAS-42: keep the object path; the URL only for old app versions.
          finalImageUrl = storageRef.fullPath;
          uploaded = true;
          legacyImageUrl = await LegacyStorageUrls.urlFor(storageRef);
        } catch (_) {
          // Keep local path if upload is unavailable so local preview still works.
        }
      }

      final toSave = PrivateLabelProductModel.fromEntity(
        product.copyWith(id: ref.id, imageUrl: finalImageUrl),
      );

      final pathStored = StorageMediaRef.isStoragePath(toSave.imageUrl);
      await ref.set({
        ...toSave.toJson(),
        // TAS-42: a new upload replaces the old URL (merge keeps fields); an
        // unchanged stored path keeps whatever URL the doc already has.
        if (uploaded) 'imageUrl': legacyImageUrl ?? FieldValue.delete(),
        if (!pathStored && toSave.imageUrl != null) 'imagePath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (product.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(_timeout);
      return toSave;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حفظ المنتج.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }

  @override
  Future<List<String>> getBranches(String organizationUID) async {
    try {
      final snap = await firestore.collection('branches').get().timeout(_timeout);
      final all = <String>{};
      final scoped = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = ((data['branchName'] ?? data['name'] ?? data['title']) ?? '')
            .toString()
            .trim();
        if (name.isEmpty) continue;
        all.add(name);
        final org = (data['organizationUID'] ?? data['organizationId'] ?? data['orgId'] ?? '')
            .toString()
            .trim();
        if (org.isNotEmpty && org == organizationUID) scoped.add(name);
      }
      final result = (scoped.isNotEmpty ? scoped : all).toList()..sort();
      return result;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحميل الفروع.');
    } on TimeoutException {
      throwTimeoutFailure();
    }
  }
}
