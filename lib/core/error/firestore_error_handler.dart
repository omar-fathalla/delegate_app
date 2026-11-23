import 'package:delegate_app/core/error/failures.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shown on permission-denied when this phone has no Firebase sign-in, so the
/// request went out unauthenticated (TAS-286, TAS-289).
const kSessionLostPermissionMessage =
    'جلستك على هذا الجهاز انتهت. سجّل الخروج من القائمة وادخل برقم الموبايل والرقم القومي.';

/// Whether a Firebase user is signed in. A seam for tests.
bool Function() firestoreHasAuthUser = _defaultHasAuthUser;

bool _defaultHasAuthUser() {
  try {
    return FirebaseAuth.instance.currentUser != null;
  } catch (_) {
    // Firebase not initialised (tests): keep the old message.
    return true;
  }
}

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
  if (e.code == 'permission-denied') {
    if (!firestoreHasAuthUser()) {
      throw const ServerFailure(kSessionLostPermissionMessage);
    }
    throw ServerFailure('$message (خطأ في الصلاحيات)');
  } else if (e.code == 'unavailable' || e.code == 'network-request-failed') {
    throw const ServerFailure('لا يوجد اتصال بالإنترنت أو الخادم غير متاح مؤقتاً. يرجى التحقق من الشبكة.');
  } else if (e.code == 'deadline-exceeded') {
    throw const ServerFailure('استغرق الاتصال بالخادم وقتاً أطول من المعتاد. يرجى التحقق من جودة الشبكة وإعادة المحاولة.');
  }
  final codeDetails = e.code.isNotEmpty ? ' [رمز الخطأ: ${e.code}]' : '';
  throw ServerFailure('$message$codeDetails');
}

Never throwTimeoutFailure([
  String message = 'انتهت مهلة الاتصال بالخادم. يرجى التحقق من الإنترنت.',
]) {
  throw ServerFailure(message);
}

Never throwUnexpectedFailure([String message = 'حدث خطأ غير متوقع.']) {
  throw ServerFailure(message);
}
