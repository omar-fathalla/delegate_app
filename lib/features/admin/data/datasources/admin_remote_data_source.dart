import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

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
      final snapshot = await _branches.get();
      return snapshot.docs
          .map((doc) => BranchModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفروع.');
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
            whereIn: ['company-admin', 'organization-admin', 'Supervisor'],
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
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('delegates')
          .get();
      return snapshot.docs
          .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة المناديب.');
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
        // Try optimized query with composite index
        snapshot = await firestore
            .collection('organizations')
            .doc(organizationId)
            .collection(kAttendanceCollection)
            .where('type', isEqualTo: 'check_in')
            .where('companyId', isEqualTo: companyId)
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
            .get();
      } catch (_) {
        // Fallback: query without timestamp range (no composite index needed)
        // Filter by date client-side
        snapshot = await firestore
            .collection('organizations')
            .doc(organizationId)
            .collection(kAttendanceCollection)
            .where('type', isEqualTo: 'check_in')
            .where('companyId', isEqualTo: companyId)
            .get();
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
      throwFirestoreFailure(e, 'فشل في جلب بيانات الحضور اليوم.');
    } catch (_) {
      return 0;
    }
  }
}
