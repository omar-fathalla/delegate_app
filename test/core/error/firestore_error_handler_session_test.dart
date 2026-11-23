import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final denied = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
  );

  tearDown(() => firestoreHasAuthUser = () => true);

  test('permission-denied without a Firebase user asks to sign in again '
      '(TAS-289)', () {
    firestoreHasAuthUser = () => false;
    expect(
      () => throwFirestoreFailure(denied, 'فشل في تسجيل الحضور.'),
      throwsA(
        isA<ServerFailure>().having(
          (f) => f.message,
          'message',
          kSessionLostPermissionMessage,
        ),
      ),
    );
  });

  test('permission-denied with a Firebase user keeps the old message', () {
    firestoreHasAuthUser = () => true;
    expect(
      () => throwFirestoreFailure(denied, 'فشل في تسجيل الحضور.'),
      throwsA(
        isA<ServerFailure>().having(
          (f) => f.message,
          'message',
          'فشل في تسجيل الحضور. (خطأ في الصلاحيات)',
        ),
      ),
    );
  });
}
