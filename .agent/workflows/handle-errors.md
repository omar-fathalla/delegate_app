---
description: Create Failure classes and map Firebase exceptions to user-friendly Arabic error messages with Either pattern.
---

# Error Handling Setup

## 1. Create base Failure class

Create `lib/core/error/failures.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({required this.message, this.code});

  @override
  List<Object?> get props => [message, code];
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});
}

class LocationFailure extends Failure {
  const LocationFailure({required super.message, super.code});
}

class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, super.code});
}

class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.code});
}
```

## 2. Create exception classes

Create `lib/core/error/exceptions.dart`:

```dart
class ServerException implements Exception {
  final String message;
  final String? code;
  const ServerException({required this.message, this.code});
}

class CacheException implements Exception {
  final String message;
  const CacheException({required this.message});
}

class LocationException implements Exception {
  final String message;
  final String? code;
  const LocationException({required this.message, this.code});
}
```

## 3. Create Firebase error mapper

Create `lib/core/error/firebase_error_mapper.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseErrorMapper {
  /// Maps FirebaseAuthException to Arabic message
  static String mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'المستخدم غير موجود';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب';
      case 'too-many-requests':
        return 'محاولات كثيرة. يرجى المحاولة لاحقاً';
      case 'invalid-verification-code':
        return 'رمز التحقق غير صحيح';
      case 'invalid-phone-number':
        return 'رقم الهاتف غير صالح';
      case 'session-expired':
        return 'انتهت الجلسة. يرجى إعادة تسجيل الدخول';
      default:
        return 'خطأ في المصادقة: ${e.message}';
    }
  }

  /// Maps FirebaseException to Arabic message
  static String mapFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية للوصول لهذه البيانات';
      case 'not-found':
        return 'البيانات المطلوبة غير موجودة';
      case 'unavailable':
        return 'الخدمة غير متاحة حالياً. يرجى المحاولة لاحقاً';
      case 'deadline-exceeded':
        return 'انتهت مهلة الطلب. تحقق من اتصالك بالإنترنت';
      case 'cancelled':
        return 'تم إلغاء العملية';
      default:
        return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى';
    }
  }

  /// Maps location errors to Arabic
  static String mapLocationError(String code) {
    switch (code) {
      case 'PERMISSION_DENIED':
        return 'يرجى السماح بالوصول إلى الموقع';
      case 'LOCATION_DISABLED':
        return 'يرجى تفعيل خدمة الموقع';
      case 'MOCK_LOCATION':
        return 'تم اكتشاف موقع وهمي. لا يمكن تسجيل الحضور';
      case 'OUT_OF_RANGE':
        return 'أنت خارج نطاق موقع العمل';
      default:
        return 'خطأ في تحديد الموقع';
    }
  }
}
```

## 4. Usage in Repository

```dart
@override
Future<Either<Failure, DelegateModel>> getDelegate(String uid) async {
  try {
    final doc = await remoteDataSource.getDelegate(uid);
    return Right(doc);
  } on FirebaseException catch (e) {
    return Left(ServerFailure(
      message: FirebaseErrorMapper.mapFirestoreError(e),
      code: e.code,
    ));
  } on FirebaseAuthException catch (e) {
    return Left(AuthFailure(
      message: FirebaseErrorMapper.mapAuthError(e),
      code: e.code,
    ));
  } catch (e) {
    return Left(const ServerFailure(
      message: 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى',
    ));
  }
}
```

## 5. Usage in Bloc

```dart
Future<void> _onLoadRequested(
  LoadRequested event,
  Emitter<FeatureState> emit,
) async {
  emit(FeatureLoading());
  final result = await useCase(event.params);
  result.fold(
    (failure) => emit(FeatureError(message: failure.message)),
    (data) => emit(FeatureLoaded(data: data)),
  );
}
```

## Rules

- ❌ Never show raw `Exception.toString()` to users.
- ❌ Never catch generic `Exception` without mapping to Arabic.
- ✅ Always use `Either<Failure, T>` in repositories.
- ✅ Map every `FirebaseException` code to a human-readable Arabic message.
- ✅ Use the `Failure.message` directly in the UI via Bloc state.
