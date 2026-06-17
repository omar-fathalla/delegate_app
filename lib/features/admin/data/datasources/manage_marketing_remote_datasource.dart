import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';

abstract class ManageMarketingRemoteDataSource {
  Future<List<AdminUserModel>> getMarketingEmployees();
  Future<void> updateMarketingEmployee(AdminUserModel employee);
  Future<void> deleteMarketingEmployee(String employeeId);
  Future<void> suspendMarketingEmployee(String employeeId, bool suspend);
}

class ManageMarketingRemoteDataSourceImpl
    implements ManageMarketingRemoteDataSource {
  final FirebaseFirestore firestore;

  ManageMarketingRemoteDataSourceImpl({required this.firestore});

  @override
  Future<List<AdminUserModel>> getMarketingEmployees() async {
    try {
      final snapshot = await firestore
          .collection('users')
          .where('role', isEqualTo: 'marketing')
          .get();
      return snapshot.docs
          .map((doc) => AdminUserModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات موظفي التسويق.');
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
  Future<void> suspendMarketingEmployee(String employeeId, bool suspend) async {
    try {
      await firestore.collection('users').doc(employeeId).update({
        'isActive': !suspend,
      });
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تغيير حالة الموظف.');
    }
  }
}
