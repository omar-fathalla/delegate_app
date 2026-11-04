import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class AdminRemoteDataSource {
  Future<List<Map<String, dynamic>>> getOrganizations();
  Future<List<BranchModel>> getBranches();
  Future<BranchModel> addBranch(BranchModel branch);
  Future<BranchModel> updateBranch(BranchModel branch);
  Future<void> deleteBranch(String branchId);
  Future<AdminUserModel> createAdmin(AdminUserModel admin);
  Future<List<AdminUserModel>> getAdmins();
  Future<void> updateAdminUser(AdminUserModel admin);
  Future<void> deleteAdminUser(String adminId);
  Future<void> suspendAdminUser(String adminId, bool suspend);
  Future<List<Map<String, dynamic>>> getCompaniesForOrg(
    String organizationUID,
  );
  Future<List<DelegateModel>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  );
  Future<int> getTodayCheckedInCount(String organizationId, String companyId);
  Future<int> getTotalCompaniesCount(String organizationId);
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseFunctions? functions;

  AdminRemoteDataSourceImpl({required this.firestore, this.functions});

  CollectionReference get _branches => firestore.collection('branches');

  @override
  Future<List<Map<String, dynamic>>> getOrganizations() async {
    try {
      final snapshot = await firestore.collection('organizations').get();
      return snapshot.docs
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب المنظمات.');
    }
  }

  @override
  Future<List<BranchModel>> getBranches() async {
    try {
      developer.log('DEBUG: getBranches called');
      final snapshot = await _branches.get();
      developer.log('DEBUG: getBranches snapshot size: ${snapshot.docs.length}');
      final branches = snapshot.docs
          .map((doc) {
            developer.log('DEBUG: Parsing branch doc: ${doc.id} -> ${doc.data()}');
            return BranchModel.fromFirestore(doc);
          })
          .toList();
      branches.sort((a, b) => a.branchName.compareTo(b.branchName));
      developer.log('DEBUG: getBranches parsed successfully: ${branches.length} branches');
      return branches;
    } on FirebaseException catch (e) {
      developer.log('DEBUG: getBranches FirebaseException: $e');
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفروع.');
    } catch (e, stack) {
      developer.log('DEBUG: getBranches Generic Exception: $e\n$stack');
      rethrow;
    }
  }

  @override
  Future<BranchModel> addBranch(BranchModel branch) async {
    try {
      final data = branch.toMap();
      final ref = await _branches.add(data);
      BranchesSessionCache.invalidate();

      // If the branch is assigned to an organization, save it directly under the organization's branches subcollection
      if (branch.organizationUID != null && branch.organizationUID!.isNotEmpty) {
        final orgBranchData = {
          ...data,
          'id': ref.id,
          'branchId': ref.id,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await firestore
            .collection('organizations')
            .doc(branch.organizationUID)
            .collection('branches')
            .doc(ref.id)
            .set(orgBranchData, SetOptions(merge: true));
      }

      return BranchModel(
        id: ref.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
        organizationUID: branch.organizationUID,
        organizationName: branch.organizationName,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إضافة الفرع.');
    }
  }

  @override
  Future<BranchModel> updateBranch(BranchModel branch) async {
    try {
      final data = branch.toUpdateMap();
      await _branches.doc(branch.id).update(data);
      BranchesSessionCache.invalidate();

      if (branch.organizationUID != null && branch.organizationUID!.isNotEmpty) {
        final orgBranchData = {
          ...data,
          'id': branch.id,
          'branchId': branch.id,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await firestore
            .collection('organizations')
            .doc(branch.organizationUID)
            .collection('branches')
            .doc(branch.id)
            .set(orgBranchData, SetOptions(merge: true));
      }

      return branch;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحديث بيانات الفرع.');
    }
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    try {
      // Check if branch belongs to an organization to clean up subcollection
      try {
        final doc = await _branches.doc(branchId).get();
        final orgUID = (doc.data() as Map<String, dynamic>?)?['organizationUID'] as String?;
        if (orgUID != null && orgUID.isNotEmpty) {
          await firestore
              .collection('organizations')
              .doc(orgUID)
              .collection('branches')
              .doc(branchId)
              .delete();
        }
      } catch (_) {}

      await _branches.doc(branchId).delete();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف الفرع.');
    } finally {
      // Always refresh the shared branches list after any delete attempt
      // (full, partial org-subcollection cleanup, or failure).
      BranchesSessionCache.invalidate();
    }
  }

  /// Staff (admin) accounts only. The createStaffUser callable creates the
  /// Firebase Auth user with no password and emails a set-password link.
  /// No password is generated, stored or sent by the app. Delegate accounts
  /// and delegate login (phone + national ID) are not affected.
  @override
  Future<AdminUserModel> createAdmin(AdminUserModel admin) async {
    try {
      final result = await (functions ?? FirebaseFunctions.instance)
          .httpsCallable('createStaffUser')
          .call<Map<String, dynamic>>({
            'email': admin.email,
            'phoneNumber': admin.phoneNumber,
            'displayName': admin.displayName,
            'role': AdminUserModel.storedRole(admin.role),
            'organizationUID': admin.organizationUID ?? '',
            'companyUID': admin.companyUID ?? '',
            if (admin.companyName != null) 'companyName': admin.companyName,
            if (admin.jobTitle != null) 'jobTitle': admin.jobTitle,
          });
      final uid = (result.data['uid'] ?? '').toString();
      return AdminUserModel(
        uid: uid,
        phoneNumber: admin.phoneNumber,
        email: admin.email,
        displayName: admin.displayName,
        role: admin.role,
        organizationUID: admin.organizationUID,
        companyUID: admin.companyUID,
        createdAt: admin.createdAt,
        createdBy: admin.createdBy,
        temporaryPassword: '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw ServerFailure(staffCreateErrorMessage(e));
    }
  }

  /// Arabic message for a createStaffUser error reason.
  static String staffCreateErrorMessage(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason']?.toString() : null;
    switch (reason) {
      case 'phone_taken':
        return 'هذا الرقم مسجل من قبل';
      case 'email_taken':
        return 'هذا الإيميل مسجل من قبل';
      case 'invalid_email':
        return 'البريد الإلكتروني غير صحيح';
      case 'invalid_phone':
        return 'رقم الهاتف غير صحيح';
      case 'rate_limited':
        return 'محاولات كثيرة. حاول لاحقاً.';
      case 'role_not_allowed':
      case 'out_of_scope':
      case 'caller_not_allowed':
      case 'super_admin_not_creatable':
      case 'not_staff_role':
        return 'ليس لديك صلاحية لإنشاء هذا الحساب.';
      default:
        return 'فشل في إنشاء حساب الأدمن.';
    }
  }

  @override
  Future<List<AdminUserModel>> getAdmins() async {
    try {
      final snapshot = await firestore
          .collection('users')
          .where(
            'role',
            whereIn: [
              'company-admin',
              'organization-admin',
              'Supervisor',
              'super-admin',
              'super_admin',
              'marketing',
              'marketing_promotion',
              'technical_support',
              'technicalSupport',
              'tech_support',
              'accountant',
              'accounting',
              'hr',
              'company-hr',
            ],
          )
          .get();
      return snapshot.docs
          .map((doc) => AdminUserModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الأدمن.');
    }
  }

  @override
  Future<void> updateAdminUser(AdminUserModel admin) async {
    try {
      await firestore.collection('users').doc(admin.uid).update({
        'displayName': admin.displayName,
        'phoneNumber': admin.phoneNumber,
        'email': admin.email,
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحديث بيانات الأدمن.');
    }
  }

  @override
  Future<void> deleteAdminUser(String adminId) async {
    try {
      await firestore.collection('users').doc(adminId).delete();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف الأدمن.');
    }
  }

  @override
  Future<void> suspendAdminUser(String adminId, bool suspend) async {
    try {
      await firestore.collection('users').doc(adminId).update({
        'isActive': !suspend,
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تغيير حالة الأدمن.');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCompaniesForOrg(
    String organizationUID,
  ) async {
    try {
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .get();
      final list = snapshot.docs
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList();
      list.sort((a, b) => (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase()));
      return list;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الشركات.');
    }
  }

  @override
  Future<List<DelegateModel>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  ) async {
    try {
      final List<DelegateModel> delegatesList = [];

      if (companyUID.isNotEmpty) {
        if (organizationUID.isNotEmpty && organizationUID != 'all') {
          // Direct path query for the specified organization - instant and never requires collectionGroup index!
          final orgDoc = await firestore
              .collection('organizations')
              .doc(organizationUID)
              .get();
          final orgName = orgDoc.data()?['name']?.toString() ?? '';
          final snap = await firestore
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .collection('delegates')
              .limit(1000)
              .get();
          for (final doc in snap.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            if ((data['organizationUID'] as String?)?.isEmpty ?? true) {
              data['organizationUID'] = organizationUID;
            }
            if ((data['organizationName'] as String?)?.isEmpty ?? true) {
              data['organizationName'] = orgName;
            }
            delegatesList.add(DelegateModel.fromJson(data, doc.id));
          }
        } else {
          // Query all active organizations in parallel via direct paths (no collectionGroup index required)
          final orgsSnap = await firestore.collection('organizations').get();
          final futures = orgsSnap.docs.map((orgDoc) async {
            final orgName = orgDoc.data()['name']?.toString() ?? '';
            final snap = await firestore
                .collection('organizations')
                .doc(orgDoc.id)
                .collection('companies')
                .doc(companyUID)
                .collection('delegates')
                .limit(1000)
                .get();
            return snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              if ((data['organizationUID'] as String?)?.isEmpty ?? true) {
                data['organizationUID'] = orgDoc.id;
              }
              if ((data['organizationName'] as String?)?.isEmpty ?? true) {
                data['organizationName'] = orgName;
              }
              return DelegateModel.fromJson(data, doc.id);
            }).toList();
          });
          final results = await Future.wait(futures);
          final Map<String, DelegateModel> unique = {};
          final Map<String, Set<String>> orgNamesByDelegate = {};
          for (final list in results) {
            for (final model in list) {
              final key = model.uid.isNotEmpty ? model.uid : model.phoneNumber;
              if (model.organizationName.isNotEmpty) {
                orgNamesByDelegate.putIfAbsent(key, () => {}).add(model.organizationName);
              }
              if (!unique.containsKey(key)) {
                unique[key] = model;
              } else {
                if (unique[key]!.status != DelegateStatus.active &&
                    unique[key]!.status != DelegateStatus.approved &&
                    (model.status == DelegateStatus.active ||
                        model.status == DelegateStatus.approved)) {
                  unique[key] = model;
                }
              }
            }
          }

          for (final entry in unique.entries) {
            final allOrgs =
                orgNamesByDelegate[entry.key]?.where((s) => s.isNotEmpty).toList() ??
                    [];
            if (allOrgs.length > 1) {
              delegatesList.add(
                entry.value.copyWith(
                  allOrganizationNames: allOrgs,
                ),
              );
            } else {
              delegatesList.add(entry.value);
            }
          }
        }
      } else if (organizationUID.isNotEmpty && organizationUID != 'all') {
        final compSnap = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .get();
        final futures = compSnap.docs.map((cDoc) => firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(cDoc.id)
            .collection('delegates')
            .limit(1000)
            .get());
        final results = await Future.wait(futures);
        final Map<String, DelegateModel> unique = {};
        for (final res in results) {
          for (final doc in res.docs) {
            final model = DelegateModel.fromJson(doc.data(), doc.id);
            unique[model.uid] = model;
          }
        }
        delegatesList.addAll(unique.values);
      } else {
        final orgsSnap = await firestore.collection('organizations').get();
        final Map<String, DelegateModel> unique = {};
        for (final orgDoc in orgsSnap.docs) {
          final compSnap = await firestore
              .collection('organizations')
              .doc(orgDoc.id)
              .collection('companies')
              .get();
          final futures = compSnap.docs.map((cDoc) => firestore
              .collection('organizations')
              .doc(orgDoc.id)
              .collection('companies')
              .doc(cDoc.id)
              .collection('delegates')
              .limit(1000)
              .get());
          final results = await Future.wait(futures);
          for (final res in results) {
            for (final doc in res.docs) {
              final model = DelegateModel.fromJson(doc.data(), doc.id);
              unique[model.uid] = model;
            }
          }
        }
        delegatesList.addAll(unique.values);
      }

      // Fetch marketing staff from /users for Organization or General Manager assignment
      // Only fetch marketing staff if this is an organization-wide query (no specific company)
      if (companyUID.isEmpty) {
        try {
          Query<Map<String, dynamic>> usersQuery = firestore
              .collection('users')
              .where('role', whereIn: ['marketing', 'marketing_promotion']);

          if (organizationUID.isNotEmpty) {
            usersQuery = usersQuery.where(
              'organizationUID',
              isEqualTo: organizationUID,
            );
          }

          final usersSnap = await usersQuery.get();
          for (final uDoc in usersSnap.docs) {
            final uData = uDoc.data();
            final uRole = uData['role'] as String? ?? '';
            final roleEnum = uRole == 'marketing'
                ? UserRole.marketing
                : uRole == 'marketing_promotion'
                    ? UserRole.marketingPromotion
                    : UserRole.delegate;

            final roleBadge = uRole == 'marketing'
                ? '📢 (تسويق الفروع)'
                : '🖼️ (تسويق العروض)';

            final dName = uData['displayName'] as String? ?? 'تسويق';

            delegatesList.add(
              DelegateModel(
                uid: uDoc.id,
                firstName: dName,
                middleName: '',
                lastName: '',
                fullName: '$dName $roleBadge',
                nationalityID: '',
                motherName: '',
                city: '',
                phoneNumber: uData['phoneNumber'] as String? ?? '',
                gender: DelegateGender.male,
                position: DelegatePosition.supervisor,
                birthDate: DateTime.now(),
                organizationUID: uData['organizationUID'] as String? ?? '',
                organizationName: uData['organizationName'] as String? ?? '',
                companyUID: '',
                companyName: '',
                status: DelegateStatus.approved,
                delegatePublicId: '',
                allReceiptCodes: const [],
                createdAt: DateTime.now(),
                createdBy: uData['createdBy'] as String? ?? '',
                hasPendingUpdate: false,
                isDeductedFromCompany: false,
                isPrinted: false,
                isProfileComplete: true,
                numberOfDocuments: 0,
                paymentAmount: 0,
                version: 1,
                documents: const [],
                role: roleEnum,
              ),
            );
          }
        } catch (_) {}
      }

      return delegatesList;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة المناديب.');
    } catch (e) {
      return [];
    }
  }

  @override
  Future<int> getTodayCheckedInCount(
    String organizationId,
    String companyId,
  ) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        Query<Map<String, dynamic>> query =
            firestore.collection(kAttendanceCollection);
        if (organizationId.isNotEmpty) {
          query = query.where('organizationId', isEqualTo: organizationId);
        }
        if (companyId.isNotEmpty) {
          query = query.where('companyId', isEqualTo: companyId);
        }
        snapshot = await query
            .where('type', isEqualTo: 'check_in')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
            .get();
      } catch (_) {
        Query<Map<String, dynamic>> query =
            firestore.collection(kAttendanceCollection);
        if (organizationId.isNotEmpty) {
          query = query.where('organizationId', isEqualTo: organizationId);
        }
        if (companyId.isNotEmpty) {
          query = query.where('companyId', isEqualTo: companyId);
        }
        snapshot = await query.where('type', isEqualTo: 'check_in').get();
      }

      // Count unique delegate IDs (only today's records)
      final uniqueDelegateIds = <String>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Client-side date filter for fallback query
        final timestamp = data['timestamp'];
        if (timestamp is Timestamp) {
          final date = timestamp.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) continue;
        }
        final delegateId = data['delegateId'] ?? data['userId'] ?? '';
        if (delegateId.isNotEmpty) {
          uniqueDelegateIds.add(delegateId);
        }
      }
      return uniqueDelegateIds.length;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') return 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<int> getTotalCompaniesCount(String organizationId) async {
    try {
      if (organizationId.isNotEmpty) {
        final snapshot = await firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('companies')
            .get();
        return snapshot.docs.length;
      } else {
        final snapshot = await firestore.collectionGroup('companies').get();
        return snapshot.docs.length;
      }
    } catch (_) {
      return 0;
    }
  }
}
