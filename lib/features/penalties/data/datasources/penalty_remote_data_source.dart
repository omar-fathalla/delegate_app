import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

import 'package:delegate_app/features/penalties/data/models/penalty_rule_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';

abstract class PenaltyRemoteDataSource {
  Future<void> createPenalty(PenaltyModel penalty);
  Future<List<PenaltyModel>> getCompanyPenalties(String companyId);
  Future<List<PenaltyModel>> getDelegatePenalties({
    required String delegateId,
    String? companyId,
    String? phoneNumber,
    String? fullName,
  });
  Future<List<PenaltyModel>> getAllPenalties();
  Future<void> updatePenaltyStatus({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  });
  Future<void> deletePenalty(String penaltyId);
  Future<void> updatePenalty(PenaltyModel penalty);
  Future<EvidenceFile> uploadEvidenceFile({
    required File file,
    required String penaltyId,
  });
  Future<List<PenaltyRuleModel>> getPenaltyRules();
  Future<void> savePenaltyRule(PenaltyRuleModel rule);
  Future<void> updatePenaltyRuleConfidentiality(String ruleId, bool isConfidential);
  Future<void> deletePenaltyRule(String ruleId);
  Future<void> seedDefaultPenaltyRules();
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
      bool isConfidential = penalty.isConfidential;
      if (!isConfidential) {
        final confidentialTitles = await _getConfidentialRuleTitles();
        final cleanTitle = penalty.title.replaceAll('(مخالفة مكررة)', '').trim().toLowerCase();
        final fullTitle = penalty.title.trim().toLowerCase();
        if (confidentialTitles.contains(cleanTitle) ||
            confidentialTitles.contains(fullTitle) ||
            confidentialTitles.any((ct) => cleanTitle.contains(ct) || ct.contains(cleanTitle))) {
          isConfidential = true;
        }
      }

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
        isConfidential: isConfidential,
        createdAt: penalty.createdAt,
        updatedAt: penalty.updatedAt,
      );

      await docRef.set(finalPenalty.toJson());

      // Comprehensive Notification Dispatching
      try {
        final fineStr = finalPenalty.fineAmount.toStringAsFixed(0);
        final branchStr = (finalPenalty.branchName != null && finalPenalty.branchName!.trim().isNotEmpty)
            ? finalPenalty.branchName!
            : 'الفرع المحدد';
        final delegateStr = (finalPenalty.targetDelegateName != null && finalPenalty.targetDelegateName!.trim().isNotEmpty)
            ? finalPenalty.targetDelegateName!
            : 'المندوب';
        final descStr = finalPenalty.incidentDescription.trim();

        // -------------------------------------------------------------
        // 1. Notification to the Target Delegate (المندوب المعني بالغرامة)
        // -------------------------------------------------------------
        if (finalPenalty.targetDelegateId != null && finalPenalty.targetDelegateId!.trim().isNotEmpty) {
          final targetDelId = finalPenalty.targetDelegateId!.trim();
          String? delPhone;
          try {
            final uDoc = await firestore.collection('users').doc(targetDelId).get();
            if (uDoc.exists) {
              delPhone = (uDoc.data()?['phoneNumber'] ?? uDoc.data()?['phone']) as String?;
            }
          } catch (_) {}

          final delTitle = 'تسجيل مخالفة جديدة بحقك';
          final delBody = 'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ $fineStr ج.م بفرع ($branchStr).'
              '${descStr.isNotEmpty ? "\nالسبب: $descStr" : ""}';

          await firestore.collection('notifications').add({
            'title': delTitle,
            'body': delBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'companyName': finalPenalty.companyName,
            'branchId': finalPenalty.branchId,
            'branchName': finalPenalty.branchName,
            'targetDelegateId': finalPenalty.targetDelegateId,
            'targetDelegateName': finalPenalty.targetDelegateName,
            'fineAmount': finalPenalty.fineAmount,
            'category': finalPenalty.category,
            'incidentDescription': finalPenalty.incidentDescription,
            'createdById': finalPenalty.createdById,
            'createdByName': finalPenalty.createdByName,
            'senderName': finalPenalty.createdByName,
            'senderRole': 'supervisor',
            'delegateUid': targetDelId,
            if (delPhone != null && delPhone.isNotEmpty) 'phoneNumber': delPhone,
            'isRead': false,
            'read': false,
            'createdAt': Timestamp.now(),
            'deletedBy': <String>[],
          });
        }

        // -------------------------------------------------------------
        // 2. Notifications to Company Supervisors & Company Admins (مشرفي ومسؤولي الشركة)
        // -------------------------------------------------------------
        final supTitle = 'مخالفة جديدة على مندوب بشركتكم (${finalPenalty.companyName})';
        final supBody = 'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بفرع ($branchStr).'
            '${descStr.isNotEmpty ? "\nالتفاصيل: $descStr" : ""}';

        final notifiedSupervisorUids = <String>{};

        // A. Direct queries for supervisors of this company in `users` collection
        try {
          final compSupervisorsSnap1 = await firestore
              .collection('users')
              .where('companyUID', isEqualTo: finalPenalty.companyId)
              .get();

          for (final uDoc in compSupervisorsSnap1.docs) {
            final uData = uDoc.data();
            final role = uData['role']?.toString().toLowerCase() ?? '';
            if (role.contains('supervisor') || role.contains('company') || role.contains('admin')) {
              notifiedSupervisorUids.add(uDoc.id);
              final phone = (uData['phoneNumber'] ?? uData['phone']) as String?;
              await firestore.collection('notifications').add({
                'title': supTitle,
                'body': supBody,
                'type': 'penalty',
                'penaltyId': docRef.id,
                'companyId': finalPenalty.companyId,
                'companyName': finalPenalty.companyName,
                'branchId': finalPenalty.branchId,
                'branchName': finalPenalty.branchName,
                'targetDelegateId': finalPenalty.targetDelegateId,
                'targetDelegateName': finalPenalty.targetDelegateName,
                'fineAmount': finalPenalty.fineAmount,
                'category': finalPenalty.category,
                'incidentDescription': finalPenalty.incidentDescription,
                'createdById': finalPenalty.createdById,
                'createdByName': finalPenalty.createdByName,
                'senderName': finalPenalty.createdByName,
                'senderRole': 'supervisor',
                'delegateUid': uDoc.id,
                if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.now(),
                'deletedBy': <String>[],
              });
            }
          }

          final compSupervisorsSnap2 = await firestore
              .collection('users')
              .where('companyId', isEqualTo: finalPenalty.companyId)
              .get();

          for (final uDoc in compSupervisorsSnap2.docs) {
            if (notifiedSupervisorUids.contains(uDoc.id)) continue;
            final uData = uDoc.data();
            final role = uData['role']?.toString().toLowerCase() ?? '';
            if (role.contains('supervisor') || role.contains('company') || role.contains('admin')) {
              notifiedSupervisorUids.add(uDoc.id);
              final phone = (uData['phoneNumber'] ?? uData['phone']) as String?;
              await firestore.collection('notifications').add({
                'title': supTitle,
                'body': supBody,
                'type': 'penalty',
                'penaltyId': docRef.id,
                'companyId': finalPenalty.companyId,
                'companyName': finalPenalty.companyName,
                'branchId': finalPenalty.branchId,
                'branchName': finalPenalty.branchName,
                'targetDelegateId': finalPenalty.targetDelegateId,
                'targetDelegateName': finalPenalty.targetDelegateName,
                'fineAmount': finalPenalty.fineAmount,
                'category': finalPenalty.category,
                'incidentDescription': finalPenalty.incidentDescription,
                'createdById': finalPenalty.createdById,
                'createdByName': finalPenalty.createdByName,
                'senderName': finalPenalty.createdByName,
                'senderRole': 'supervisor',
                'delegateUid': uDoc.id,
                if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.now(),
                'deletedBy': <String>[],
              });
            }
          }
        } catch (_) {}

        // B. Company & Supervisor channel broadcast records
        final supTargets = finalPenalty.isConfidential
            ? [
                'company_${finalPenalty.companyId}',
                'supervisor_${finalPenalty.companyId}',
              ]
            : [
                'company_${finalPenalty.companyId}',
                'supervisor_${finalPenalty.companyId}',
                'all_company_supervisors',
              ];

        for (final targetKey in supTargets) {
          await firestore.collection('notifications').add({
            'title': supTitle,
            'body': supBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'companyName': finalPenalty.companyName,
            'branchId': finalPenalty.branchId,
            'branchName': finalPenalty.branchName,
            'targetDelegateId': finalPenalty.targetDelegateId,
            'targetDelegateName': finalPenalty.targetDelegateName,
            'fineAmount': finalPenalty.fineAmount,
            'category': finalPenalty.category,
            'incidentDescription': finalPenalty.incidentDescription,
            'createdById': finalPenalty.createdById,
            'createdByName': finalPenalty.createdByName,
            'senderName': finalPenalty.createdByName,
            'senderRole': 'supervisor',
            'delegateUid': targetKey,
            'isRead': false,
            'read': false,
            'createdAt': Timestamp.now(),
            'deletedBy': <String>[],
          });
        }

        // -------------------------------------------------------------
        // 3. Notifications to Branches Marketing Manager (المرحلة الأولى للاعتماد)
        // -------------------------------------------------------------
        final isDirect = finalPenalty.fineAmount <= 1000.0;
        final bmmTitle = 'مخالفة جديدة قيد مراجعتك واعتمادك';
        final bmmBody = isDirect
            ? 'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${finalPenalty.companyName}) بفرع ($branchStr). المخالفة ضمن صلاحية اعتمادك وإصدارك الفوري (≤ 1000 ج.م).'
            : 'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${finalPenalty.companyName}) بفرع ($branchStr). المخالفة تتطلب مراجعتك وتمريرها للمدير العام (> 1000 ج.م).';

        if (!finalPenalty.isConfidential) {
          for (final roleKey in ['branchesMarketingManager', 'branches_marketing', 'marketing']) {
            await firestore.collection('notifications').add({
              'title': bmmTitle,
              'body': bmmBody,
              'type': 'penalty',
              'penaltyId': docRef.id,
              'companyId': finalPenalty.companyId,
              'companyName': finalPenalty.companyName,
              'branchId': finalPenalty.branchId,
              'branchName': finalPenalty.branchName,
              'targetDelegateId': finalPenalty.targetDelegateId,
              'targetDelegateName': finalPenalty.targetDelegateName,
              'fineAmount': finalPenalty.fineAmount,
              'category': finalPenalty.category,
              'incidentDescription': finalPenalty.incidentDescription,
              'createdById': finalPenalty.createdById,
              'createdByName': finalPenalty.createdByName,
              'senderName': finalPenalty.createdByName,
              'senderRole': 'supervisor',
              'delegateUid': roleKey,
              'isRead': false,
              'read': false,
              'createdAt': Timestamp.now(),
              'deletedBy': <String>[],
            });
          }
        }

        // -------------------------------------------------------------
        // 4. Notifications to General Management / Super Admin / Tech Support
        // -------------------------------------------------------------
        final gmTitle = finalPenalty.isConfidential
            ? 'إشعار تسجيل مخالفة سرية على النظام'
            : 'إشعار تسجيل مخالفة جديدة على النظام';
        final gmBody = finalPenalty.isConfidential
            ? 'تم تسجيل مخالفة سرية (${finalPenalty.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${finalPenalty.companyName}).'
            : 'تم تسجيل مخالفة (${finalPenalty.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${finalPenalty.companyName}) بفرع ($branchStr)، وهي الآن قيد المراجعة والاعتماد الأول من مدير تسويق الفروع.';

        final adminRoleKeys = finalPenalty.isConfidential
            ? ['organizationAdmin', 'super-admin', 'superAdmin', 'technicalSupport', 'technical_support']
            : ['organizationAdmin', 'super-admin'];

        for (final roleKey in adminRoleKeys) {
          await firestore.collection('notifications').add({
            'title': gmTitle,
            'body': gmBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'companyName': finalPenalty.companyName,
            'branchId': finalPenalty.branchId,
            'branchName': finalPenalty.branchName,
            'targetDelegateId': finalPenalty.targetDelegateId,
            'targetDelegateName': finalPenalty.targetDelegateName,
            'fineAmount': finalPenalty.fineAmount,
            'category': finalPenalty.category,
            'incidentDescription': finalPenalty.incidentDescription,
            'createdById': finalPenalty.createdById,
            'createdByName': finalPenalty.createdByName,
            'senderName': finalPenalty.createdByName,
            'senderRole': 'supervisor',
            'delegateUid': roleKey,
            'isRead': false,
            'read': false,
            'createdAt': Timestamp.now(),
            'deletedBy': <String>[],
          });
        }

        // Direct manager user accounts in Firestore
        final queryRoles = finalPenalty.isConfidential
            ? ['organizationAdmin', 'superAdmin', 'super-admin', 'technicalSupport', 'technical_support']
            : ['branchesMarketingManager', 'organizationAdmin', 'superAdmin', 'super-admin', 'branches_marketing'];

        final usersSnap = await firestore
            .collection('users')
            .where('role', whereIn: queryRoles)
            .get();

        for (final userDoc in usersSnap.docs) {
          final uid = userDoc.id;
          final phone = userDoc.data()['phoneNumber']?.toString();
          final userRole = userDoc.data()['role']?.toString().toLowerCase() ?? '';
          final isBmm = userRole.contains('marketing') || userRole.contains('branches');

          if (finalPenalty.isConfidential && isBmm) continue;

          await firestore.collection('notifications').add({
            'title': isBmm ? bmmTitle : gmTitle,
            'body': isBmm ? bmmBody : gmBody,
            'type': 'penalty',
            'penaltyId': docRef.id,
            'companyId': finalPenalty.companyId,
            'companyName': finalPenalty.companyName,
            'branchId': finalPenalty.branchId,
            'branchName': finalPenalty.branchName,
            'targetDelegateId': finalPenalty.targetDelegateId,
            'targetDelegateName': finalPenalty.targetDelegateName,
            'fineAmount': finalPenalty.fineAmount,
            'category': finalPenalty.category,
            'incidentDescription': finalPenalty.incidentDescription,
            'createdById': finalPenalty.createdById,
            'createdByName': finalPenalty.createdByName,
            'senderName': finalPenalty.createdByName,
            'senderRole': 'supervisor',
            'delegateUid': uid,
            if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
            'isRead': false,
            'read': false,
            'createdAt': Timestamp.now(),
            'deletedBy': <String>[],
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

  Set<String> _confidentialRuleTitlesCache = {};
  DateTime? _lastConfidentialRulesFetch;

  Future<Set<String>> _getConfidentialRuleTitles() async {
    final now = DateTime.now();
    if (_lastConfidentialRulesFetch != null &&
        now.difference(_lastConfidentialRulesFetch!) < const Duration(minutes: 2) &&
        _confidentialRuleTitlesCache.isNotEmpty) {
      return _confidentialRuleTitlesCache;
    }
    try {
      final rulesSnap = await _penaltyRulesRef
          .where('isConfidential', isEqualTo: true)
          .get();
      final titles = <String>{};
      for (final doc in rulesSnap.docs) {
        final data = doc.data();
        if (data['title'] != null) {
          final t = data['title'].toString().trim().toLowerCase();
          titles.add(t);
        }
      }
      _confidentialRuleTitlesCache = titles;
      _lastConfidentialRulesFetch = now;
      return titles;
    } catch (_) {
      return _confidentialRuleTitlesCache;
    }
  }

  List<PenaltyModel> _enrichPenaltiesWithConfidentiality(
    List<PenaltyModel> list,
    Set<String> confidentialTitles,
  ) {
    if (confidentialTitles.isEmpty) return list;
    return list.map((p) {
      if (p.isConfidential) return p;
      final cleanTitle = p.title.replaceAll('(مخالفة مكررة)', '').trim().toLowerCase();
      final fullTitle = p.title.trim().toLowerCase();
      if (confidentialTitles.contains(cleanTitle) ||
          confidentialTitles.contains(fullTitle) ||
          confidentialTitles.any((ct) => cleanTitle.contains(ct) || ct.contains(cleanTitle))) {
        return PenaltyModel(
          penaltyId: p.penaltyId,
          companyId: p.companyId,
          companyName: p.companyName,
          branchId: p.branchId,
          branchName: p.branchName,
          createdById: p.createdById,
          createdByName: p.createdByName,
          createdByPhone: p.createdByPhone,
          title: p.title,
          category: p.category,
          incidentDescription: p.incidentDescription,
          fineAmount: p.fineAmount,
          currency: p.currency,
          status: p.status,
          evidenceFiles: p.evidenceFiles,
          branchesMarketingApprovedBy: p.branchesMarketingApprovedBy,
          branchesMarketingApprovedAt: p.branchesMarketingApprovedAt,
          generalManagerApprovedBy: p.generalManagerApprovedBy,
          generalManagerApprovedAt: p.generalManagerApprovedAt,
          rejectionReason: p.rejectionReason,
          targetDelegateId: p.targetDelegateId,
          targetDelegateName: p.targetDelegateName,
          isRepeated: p.isRepeated,
          isConfidential: true,
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
        );
      }
      return p;
    }).toList();
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
      final confidentialTitles = await _getConfidentialRuleTitles();
      return _enrichPenaltiesWithConfidentiality(list, confidentialTitles);
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في جلب قائمة المخالفات.');
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<PenaltyModel>> getDelegatePenalties({
    required String delegateId,
    String? companyId,
    String? phoneNumber,
    String? fullName,
  }) async {
    try {
      final Map<String, PenaltyModel> results = {};

      // 1. Direct query by targetDelegateId == delegateId
      try {
        final snap = await _penaltiesRef
            .where('targetDelegateId', isEqualTo: delegateId)
            .get();
        for (var doc in snap.docs) {
          results[doc.id] = PenaltyModel.fromFirestore(doc);
        }
      } catch (_) {}

      // 2. Query company's penalties and match personal identifiers
      if (companyId != null && companyId.isNotEmpty) {
        try {
          final compSnap = await _penaltiesRef
              .where('companyId', isEqualTo: companyId)
              .get();
          for (var doc in compSnap.docs) {
            final model = PenaltyModel.fromFirestore(doc);
            if (_isPenaltyMatchingDelegate(
              model,
              delegateId: delegateId,
              phoneNumber: phoneNumber,
              fullName: fullName,
            )) {
              results[doc.id] = model;
            }
          }
        } catch (_) {}
      }

      final list = results.values.toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final confidentialTitles = await _getConfidentialRuleTitles();
      return _enrichPenaltiesWithConfidentiality(list, confidentialTitles);
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في جلب مخالفات المندوب.');
    } catch (_) {
      return [];
    }
  }

  bool _isPenaltyMatchingDelegate(
    PenaltyModel p, {
    required String delegateId,
    String? phoneNumber,
    String? fullName,
  }) {
    if (p.targetDelegateId != null && p.targetDelegateId!.trim().isNotEmpty) {
      final tid = p.targetDelegateId!.trim();
      if (tid == delegateId) return true;
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        final cleanTid = tid.replaceAll(RegExp(r'\D'), '');
        final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
        if (cleanTid.isNotEmpty && cleanPhone.isNotEmpty) {
          if (cleanTid == cleanPhone ||
              cleanTid.endsWith(cleanPhone) ||
              cleanPhone.endsWith(cleanTid)) {
            return true;
          }
        }
      }
    }

    if (fullName != null && fullName.trim().isNotEmpty &&
        p.targetDelegateName != null && p.targetDelegateName!.trim().isNotEmpty) {
      final tName = p.targetDelegateName!.trim().toLowerCase();
      final fName = fullName.trim().toLowerCase();
      if (tName == fName) return true;
    }

    return false;
  }

  @override
  Future<List<PenaltyModel>> getAllPenalties() async {
    try {
      final snapshot = await _penaltiesRef.get();
      final list = snapshot.docs
          .map((doc) => PenaltyModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final confidentialTitles = await _getConfidentialRuleTitles();
      return _enrichPenaltiesWithConfidentiality(list, confidentialTitles);
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

      // Notify relevant parties of status update
      try {
        final penDoc = await _penaltiesRef.doc(penaltyId).get();
        if (penDoc.exists) {
          final pen = PenaltyModel.fromFirestore(penDoc);
          final statusLabel = pen.status.displayName;
          final fineStr = pen.fineAmount.toStringAsFixed(0);
          final branchStr = (pen.branchName != null && pen.branchName!.trim().isNotEmpty) ? pen.branchName! : 'الفرع';
          final delegateStr = (pen.targetDelegateName != null && pen.targetDelegateName!.trim().isNotEmpty) ? pen.targetDelegateName! : 'المندوب';
          final revName = reviewerName ?? 'المسؤول';

          final revRole = (status == PenaltyStatus.issued ||
                  status == PenaltyStatus.rejectedByGeneralManager)
              ? 'superAdmin'
              : 'branchesMarketingManager';

          String updateTitle = 'تحديث حالة المخالفة';
          String updateBody = 'تم تحديث حالة مخالفة (${pen.title}) على المندوب ($delegateStr) بشركة (${pen.companyName}) إلى: $statusLabel.';

          if (status == PenaltyStatus.pendingGeneralManager) {
            // 1. Forwarded to General Manager (> 1000 EGP)
            final gmPendingTitle = 'مخالفة بانتظار اعتماد سيادتكم النهائي (> 1000 ج.م)';
            final gmPendingBody = 'قام مدير تسويق الفروع ($revName) بالموافقة على مخالفة (${pen.title}) بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${pen.companyName}) بفرع ($branchStr). المخالفة الآن بانتظار اعتماد سيادتكم النهائي.';

            for (final r in ['organizationAdmin', 'super-admin']) {
              await firestore.collection('notifications').add({
                'title': gmPendingTitle,
                'body': gmPendingBody,
                'type': 'penalty',
                'penaltyId': penaltyId,
                'companyId': pen.companyId,
                'companyName': pen.companyName,
                'branchId': pen.branchId,
                'branchName': pen.branchName,
                'targetDelegateId': pen.targetDelegateId,
                'targetDelegateName': pen.targetDelegateName,
                'fineAmount': pen.fineAmount,
                'senderName': revName,
                'senderRole': 'branchesMarketingManager',
                'delegateUid': r,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.now(),
                'deletedBy': <String>[],
              });
            }

            updateTitle = 'تمرير المخالفة للاعتماد النهائي';
            updateBody = 'تمت الموافقة المبدئية من تسويق الفروع ($revName) وتمرير المخالفة (${pen.title}) بمبلغ $fineStr ج.م للاعتماد النهائي من المدير العام.';
          } else if (status == PenaltyStatus.issued) {
            // 2. Officially Issued / Approved
            updateTitle = 'اعتماد وصدور غرامة رسمية';
            updateBody = 'تم اعتماد الغرامة رسمياً بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${pen.companyName}) بفرع ($branchStr) من قبل ($revName).';

            // Also inform Branches Marketing Manager if approved by GM
            for (final r in ['branchesMarketingManager', 'branches_marketing']) {
              await firestore.collection('notifications').add({
                'title': 'اعتماد نهائي للغرامة',
                'body': 'اعتمد $revName الغرامة رسمياً بمبلغ $fineStr ج.م على المندوب ($delegateStr) بشركة (${pen.companyName}).',
                'type': 'penalty',
                'penaltyId': penaltyId,
                'companyId': pen.companyId,
                'companyName': pen.companyName,
                'branchId': pen.branchId,
                'branchName': pen.branchName,
                'targetDelegateId': pen.targetDelegateId,
                'targetDelegateName': pen.targetDelegateName,
                'fineAmount': pen.fineAmount,
                'senderName': revName,
                'senderRole': 'superAdmin',
                'delegateUid': r,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.now(),
                'deletedBy': <String>[],
              });
            }
          } else if (status == PenaltyStatus.deducted) {
            updateTitle = 'خصم قيمة المخالفة';
            updateBody = 'تم خصم قيمة المخالفة ($fineStr ج.م) للمندوب ($delegateStr) من مستحقات شركة (${pen.companyName}).';
          } else if (status == PenaltyStatus.rejectedByBranchesMarketing || status == PenaltyStatus.rejectedByGeneralManager) {
            updateTitle = 'رفض وإلغاء الغرامة';
            updateBody = 'تم رفض وإلغاء المخالفة (${pen.title}) على المندوب ($delegateStr) من قبل ($revName).'
                '${rejectionReason != null && rejectionReason.isNotEmpty ? "\nسبب الرفض: $rejectionReason" : ""}';
          }

          // Notify delegate
          if (pen.targetDelegateId != null && pen.targetDelegateId!.isNotEmpty) {
            await firestore.collection('notifications').add({
              'title': updateTitle,
              'body': updateBody,
              'type': 'penalty',
              'penaltyId': penaltyId,
              'companyId': pen.companyId,
              'companyName': pen.companyName,
              'branchId': pen.branchId,
              'branchName': pen.branchName,
              'targetDelegateId': pen.targetDelegateId,
              'targetDelegateName': pen.targetDelegateName,
              'fineAmount': pen.fineAmount,
              'senderName': revName,
              'senderRole': revRole,
              'delegateUid': pen.targetDelegateId,
              'isRead': false,
              'read': false,
              'createdAt': Timestamp.now(),
              'deletedBy': <String>[],
            });
          }

          // Notify company supervisors
          await firestore.collection('notifications').add({
            'title': updateTitle,
            'body': updateBody,
            'type': 'penalty',
            'penaltyId': penaltyId,
            'companyId': pen.companyId,
            'companyName': pen.companyName,
            'branchId': pen.branchId,
            'branchName': pen.branchName,
            'targetDelegateId': pen.targetDelegateId,
            'targetDelegateName': pen.targetDelegateName,
            'fineAmount': pen.fineAmount,
            'senderName': revName,
            'senderRole': revRole,
            'delegateUid': 'company_${pen.companyId}',
            'isRead': false,
            'read': false,
            'createdAt': Timestamp.now(),
            'deletedBy': <String>[],
          });
        }
      } catch (_) {}
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في تحديث حالة المخالفة.');
    } catch (e) {
      throw ServerException('حدث خطأ غير متوقع أثناء تحديث حالة المخالفة.');
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
  Future<void> updatePenalty(PenaltyModel penalty) async {
    try {
      await _penaltiesRef.doc(penalty.penaltyId).set(
            penalty.toJson(),
            SetOptions(merge: true),
          );
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'فشل في تعديل بيانات المخالفة.');
    } catch (_) {
      throw ServerException('حدث خطأ غير متوقع أثناء تعديل بيانات المخالفة.');
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

  CollectionReference<Map<String, dynamic>> get _penaltyRulesRef =>
      firestore.collection('penalty_rules');

  @override
  Future<List<PenaltyRuleModel>> getPenaltyRules() async {
    try {
      final snapshot = await _penaltyRulesRef.orderBy('createdAt', descending: false).get();
      if (snapshot.docs.isEmpty) {
        // Auto seed default standard violations to Firestore
        await seedDefaultPenaltyRules();
        final seeded = await _penaltyRulesRef.orderBy('createdAt', descending: false).get();
        if (seeded.docs.isNotEmpty) {
          return seeded.docs.map((doc) => PenaltyRuleModel.fromFirestore(doc)).toList();
        }
      } else {
        return snapshot.docs.map((doc) => PenaltyRuleModel.fromFirestore(doc)).toList();
      }

      // Fallback if empty
      return officialViolationsSchedule.map((v) => PenaltyRuleModel(
        id: 'standard_${v.id}',
        title: v.title,
        defaultFine: v.defaultFine,
        repeatedFine: v.repeatedFine,
        isConfidential: false,
        category: v.category,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'system_default',
      )).toList();
    } catch (e) {
      // Offline / fallback from official schedule
      return officialViolationsSchedule.map((v) => PenaltyRuleModel(
        id: 'standard_${v.id}',
        title: v.title,
        defaultFine: v.defaultFine,
        repeatedFine: v.repeatedFine,
        isConfidential: false,
        category: v.category,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'system_default',
      )).toList();
    }
  }

  @override
  Future<void> savePenaltyRule(PenaltyRuleModel rule) async {
    try {
      final docRef = rule.id.isNotEmpty && !rule.id.startsWith('temp_')
          ? _penaltyRulesRef.doc(rule.id)
          : _penaltyRulesRef.doc();
      final modelToSave = PenaltyRuleModel(
        id: docRef.id,
        title: rule.title,
        defaultFine: rule.defaultFine,
        repeatedFine: rule.repeatedFine,
        isConfidential: rule.isConfidential,
        category: rule.category,
        createdAt: rule.createdAt,
        updatedAt: DateTime.now(),
        createdBy: rule.createdBy,
      );
      await docRef.set(modelToSave.toJson(), SetOptions(merge: true));
    } catch (e) {
      throw ServerException('فشل في حفظ إعدادات بند الغرامة: $e');
    }
  }

  @override
  Future<void> updatePenaltyRuleConfidentiality(String ruleId, bool isConfidential) async {
    try {
      final ruleDoc = await _penaltyRulesRef.doc(ruleId).get();
      final ruleData = ruleDoc.data();
      final ruleTitle = ruleData?['title'] as String?;

      await _penaltyRulesRef.doc(ruleId).update({
        'isConfidential': isConfidential,
        'updatedAt': Timestamp.now(),
      });
      _lastConfidentialRulesFetch = null;

      // Synchronize all existing penalties matching this rule's title
      if (ruleTitle != null && ruleTitle.trim().isNotEmpty) {
        final penaltiesSnap = await _penaltiesRef
            .where('title', isEqualTo: ruleTitle.trim())
            .get();
        if (penaltiesSnap.docs.isNotEmpty) {
          final batch = firestore.batch();
          for (final doc in penaltiesSnap.docs) {
            batch.update(doc.reference, {
              'isConfidential': isConfidential,
              'updatedAt': Timestamp.now(),
            });
          }
          await batch.commit();
        }
      }
    } catch (e) {
      throw ServerException('فشل في تعديل حالة سرية الغرامة: $e');
    }
  }

  @override
  Future<void> deletePenaltyRule(String ruleId) async {
    try {
      await _penaltyRulesRef.doc(ruleId).delete();
    } catch (e) {
      throw ServerException('فشل في حذف بند الغرامة: $e');
    }
  }

  @override
  Future<void> seedDefaultPenaltyRules() async {
    try {
      final batch = firestore.batch();
      for (final v in officialViolationsSchedule) {
        final docRef = _penaltyRulesRef.doc('standard_${v.id}');
        final model = PenaltyRuleModel(
          id: docRef.id,
          title: v.title,
          defaultFine: v.defaultFine,
          repeatedFine: v.repeatedFine,
          isConfidential: false,
          category: v.category,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: 'system_default',
        );
        batch.set(docRef, model.toJson());
      }
      await batch.commit();
    } catch (_) {}
  }
}
