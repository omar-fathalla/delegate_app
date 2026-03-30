import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('throwFirestoreFailure', () {
    test('throws ServerFailure with the provided message', () {
      final exception = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
      );

      expect(
        () => throwFirestoreFailure(exception, 'فشل في تسجيل الحضور.'),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            'فشل في تسجيل الحضور.',
          ),
        ),
      );
    });

    test('throws ServerFailure regardless of Firebase error code', () {
      final permissionDenied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      expect(
        () => throwFirestoreFailure(permissionDenied, 'غير مصرح'),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('throwTimeoutFailure', () {
    test('throws ServerFailure with default timeout message', () {
      expect(
        () => throwTimeoutFailure(),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            'انتهت مهلة الاتصال بالخادم. يرجى التحقق من الإنترنت.',
          ),
        ),
      );
    });

    test('throws ServerFailure with custom message', () {
      expect(
        () => throwTimeoutFailure('انتهت المهلة المخصصة.'),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            'انتهت المهلة المخصصة.',
          ),
        ),
      );
    });
  });

  group('throwUnexpectedFailure', () {
    test('throws ServerFailure with default message', () {
      expect(
        () => throwUnexpectedFailure(),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            'حدث خطأ غير متوقع.',
          ),
        ),
      );
    });

    test('throws ServerFailure with custom message', () {
      expect(
        () => throwUnexpectedFailure('خطأ مخصص'),
        throwsA(
          isA<ServerFailure>().having((f) => f.message, 'message', 'خطأ مخصص'),
        ),
      );
    });
  });
}
