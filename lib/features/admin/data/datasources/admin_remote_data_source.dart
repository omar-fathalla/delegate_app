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
  Future<void> sendActivationEmail({
    required String email,
    required String phoneNumber,
    required String temporaryPassword,
    required String displayName,
  });
  Future<List<DelegateModel>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  );
  Future<int> getTodayCheckedInCount(String organizationId, String companyId);
  Future<int> getTotalCompaniesCount(String organizationId);
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final FirebaseFirestore firestore;

  AdminRemoteDataSourceImpl({required this.firestore});

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
      final ref = await _branches.add(branch.toMap());
      return BranchModel(
        id: ref.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إضافة الفرع.');
    }
  }

  @override
  Future<BranchModel> updateBranch(BranchModel branch) async {
    try {
      await _branches.doc(branch.id).update(branch.toMap());
      return branch;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحديث بيانات الفرع.');
    }
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    try {
      await _branches.doc(branchId).delete();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف الفرع.');
    }
  }

  @override
  Future<AdminUserModel> createAdmin(AdminUserModel admin) async {
    try {
      // Check if phone number already exists
      final phoneQuery = await firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: admin.phoneNumber)
          .get();
          
      if (phoneQuery.docs.isNotEmpty) {
        throw const ServerFailure('هذا الرقم مسجل من قبل');
      }

      // Check if email already exists (only if email is provided)
      if (admin.email.isNotEmpty) {
        final emailQuery = await firestore
            .collection('users')
            .where('email', isEqualTo: admin.email)
            .get();
            
        if (emailQuery.docs.isNotEmpty) {
          throw const ServerFailure('هذا الإيميل مسجل من قبل');
        }
      }

      final ref = await firestore.collection('users').add(admin.toMap());
      return AdminUserModel(
        uid: ref.id,
        phoneNumber: admin.phoneNumber,
        email: admin.email,
        displayName: admin.displayName,
        role: admin.role,
        organizationUID: admin.organizationUID,
        companyUID: admin.companyUID,
        createdAt: admin.createdAt,
        createdBy: admin.createdBy,
        temporaryPassword: admin.temporaryPassword,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إنشاء حساب الأدمن.');
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
              'marketing',
              'marketing_promotion',
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
  Future<void> sendActivationEmail({
    required String email,
    required String phoneNumber,
    required String temporaryPassword,
    required String displayName,
  }) async {
    try {
      await firestore.collection('mail').add({
        'to': [email],
        'message': {
          'subject': 'Tashil - تفعيل حساب Admin',
          'html':
              '''
<div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="background: #1a73e8; padding: 24px; border-radius: 12px 12px 0 0; text-align: center;">
    <h1 style="color: white; margin: 0; font-size: 28px;">Tashil - تسهيل</h1>
  </div>
  <div style="background: #ffffff; padding: 32px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
    <h2 style="color: #333;">مرحباً $displayName</h2>
    <p style="color: #555; font-size: 16px;">
      تم إنشاء حساب Admin لك على منصة تسهيل.
    </p>
    <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
      <p style="margin: 8px 0;"><strong>رقم الهاتف:</strong> $phoneNumber</p>
      <p style="margin: 8px 0;"><strong>كلمة السر المؤقتة:</strong> $temporaryPassword</p>
    </div>
    <p style="color: #555;">
      قم بتحميل تطبيق تسهيل وسجل الدخول بالبيانات أعلاه.
    </p>
    <hr style="border: none; border-top: 1px solid #eee; margin: 24px 0;">
    <p style="color: #999; font-size: 12px; text-align: center;">
      هذه رسالة تلقائية من تسهيل. لا ترد عليها.
    </p>
  </div>
</div>
''',
        },
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إرسال بريد التفعيل.');
    }
  }

  @override
  Future<List<DelegateModel>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  ) async {
    try {
      final List<DelegateModel> delegatesList = [];

      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (organizationUID.isEmpty) {
        snapshot = await firestore.collectionGroup('delegates').limit(1000).get();
      } else if (companyUID.isEmpty) {
        snapshot = await firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID)
            .limit(1000)
            .get();
      } else {
        snapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .limit(1000)
            .get();
      }

      delegatesList.addAll(
        snapshot.docs.map((doc) => DelegateModel.fromJson(doc.data(), doc.id)),
      );

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
