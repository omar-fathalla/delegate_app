import 'dart:async';

import 'package:delegate_app/core/error/failures.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    _healAnonymousSession();
    throw ServerFailure('$message (خطأ في الصلاحيات، يرجى إعادة المحاولة)');
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

/// Attempts to silently refresh the anonymous authentication session in the background.
/// This fixes `permission-denied` errors caused by expired anonymous tokens.
Future<void> _healAnonymousSession() async {
  try {
    final auth = FirebaseAuth.instance;
    // Only heal if they are currently logged in anonymously or not logged in at all.
    // We avoid touching Email/Password sessions (like Admins).
    if (auth.currentUser?.isAnonymous == true) {
      await auth.signOut();
      await auth.signInAnonymously();
    } else if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  } catch (_) {
    // Ignore errors during background healing
  }
}
