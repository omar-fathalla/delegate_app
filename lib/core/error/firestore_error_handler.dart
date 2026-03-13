import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';

/// Handles Firestore-related exceptions and throws the appropriate [ServerFailure].
///
/// Call this in a catch clause to convert [FirebaseException] and
/// [TimeoutException] into domain [ServerFailure] objects.
///
/// Example:
/// ```dart
/// } on FirebaseException catch (e) {
///   throwFirestoreFailure(e, 'فشل في تسجيل الحضور.');
/// } on TimeoutException {
///   throwTimeoutFailure();
/// } catch (_) {
///   throwUnexpectedFailure('حدث خطأ غير متوقع.');
/// }
/// ```
Never throwFirestoreFailure(FirebaseException e, String message) {
  throw ServerFailure(message);
}

Never throwTimeoutFailure([
  String message = 'انتهت مهلة الاتصال بالخادم. يرجى التحقق من الإنترنت.',
]) {
  throw ServerFailure(message);
}

Never throwUnexpectedFailure([String message = 'حدث خطأ غير متوقع.']) {
  throw ServerFailure(message);
}
