import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';

abstract class ManageMarketingRemoteDataSource {
  /// TAS-73: company staff see their company, org-scoped staff their
  /// organization; only global staff (both empty) read every user.
  Future<List<AdminUserModel>> getMarketingEmployees({String companyUID = '', String organizationUID = ''});
  Future<void> updateMarketingEmployee(AdminUserModel employee);
  Future<void> deleteMarketingEmployee(String employeeId);
  Future<void> suspendMarketingEmployee(String employeeId, bool suspend);
}

class ManageMarketingRemoteDataSourceImpl
    implements ManageMarketingRemoteDataSource {
  final FirebaseFirestore firestore;

  ManageMarketingRemoteDataSourceImpl({required this.firestore});

  @override
  Future<List<AdminUserModel>> getMarketingEmployees({String companyUID = '', String organizationUID = ''}) async {
    try {
      // 1. Fetch organizations to resolve organization names dynamically
      final orgMap = <String, String>{};
      try {
        final orgsSnapshot = await firestore.collection('organizations').get();
        for (final doc in orgsSnapshot.docs) {
          final d = doc.data();
          final name = (d['name'] ?? d['title'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            orgMap[doc.id] = name;
            final oUid = d['organizationUID']?.toString().trim();
            if (oUid != null && oUid.isNotEmpty) {
              orgMap[oUid] = name;
            }
            final uid = d['uid']?.toString().trim();
            if (uid != null && uid.isNotEmpty) {
              orgMap[uid] = name;
            }
          }
        }
      } catch (_) {
        // Fallback gracefully if organizations fetch fails
      }

      Query<Map<String, dynamic>> usersQuery = firestore.collection('users');
      if (companyUID.trim().isNotEmpty) {
        usersQuery = usersQuery.where('companyUID', isEqualTo: companyUID.trim());
      } else if (organizationUID.trim().isNotEmpty) {
        usersQuery =
            usersQuery.where('organizationUID', isEqualTo: organizationUID.trim());
      }
      final snapshot = await usersQuery.get();
      final list = <AdminUserModel>[];
      for (final doc in snapshot.docs) {
        try {
          list.add(AdminUserModel.fromFirestore(doc, orgMap));
        } catch (_) {
          // Keep resilient against any isolated malformed doc
        }
      }
      return list;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات المستخدمين.');
    }
  }

  @override
  Future<void> updateMarketingEmployee(AdminUserModel employee) async {
    try {
      await firestore.collection('users').doc(employee.uid).update({
        'displayName': employee.displayName,
        'phoneNumber': employee.phoneNumber,
        'email': employee.email,
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحديث بيانات الموظف.');
    }
  }

  @override
  Future<void> deleteMarketingEmployee(String employeeId) async {
    try {
      await firestore.collection('users').doc(employeeId).delete();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف الموظف.');
    }
  }

  @override
  Future<void> suspendMarketingEmployee(
    String employeeId,
    bool suspend,
  ) async {
    try {
      await firestore.collection('users').doc(employeeId).update({
        'isActive': !suspend,
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تغيير حالة الموظف.');
    }
  }
}
