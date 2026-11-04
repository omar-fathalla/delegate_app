import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AdminUserModel.toMap never writes a password', () {
    final m = AdminUserModel(
      uid: 'u',
      phoneNumber: '01000000000',
      email: 'a@b.c',
      displayName: 'A',
      role: 'hr',
      createdAt: DateTime(2026),
      createdBy: 'sa',
      temporaryPassword: 'should-not-be-written',
    ).toMap();
    for (final k in ['password', 'temporaryPassword', 'tempPassword']) {
      expect(m.containsKey(k), isFalse, reason: k);
    }
  });

  test('fromFirestore does not load a stored legacy password', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/x').set({'role': 'hr', 'password': 'legacy'});
    final m = AdminUserModel.fromFirestore(await db.doc('users/x').get());
    expect(m.temporaryPassword, isEmpty);
  });

  test('createStaffUser reasons map to Arabic messages', () {
    String msg(String reason) =>
        AdminRemoteDataSourceImpl.staffCreateErrorMessage(
          FirebaseFunctionsException(
            code: 'x',
            message: reason,
            details: {'reason': reason},
          ),
        );
    expect(msg('phone_taken'), 'هذا الرقم مسجل من قبل');
    expect(msg('email_taken'), 'هذا الإيميل مسجل من قبل');
    expect(msg('role_not_allowed'), 'ليس لديك صلاحية لإنشاء هذا الحساب.');
    expect(msg('other'), 'فشل في إنشاء حساب الأدمن.');
  });
}
