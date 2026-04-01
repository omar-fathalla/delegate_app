import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class Login implements UseCase<List<Delegate>, LoginParams> {
  final AuthRepository repository;

  Login(this.repository);

  @override
  Future<Either<Failure, List<Delegate>>> call(LoginParams params) async {
    // 1. جلب بيانات المندوب من السيرفر بناء على رقم الهاتف
    final result = await repository.getDelegatesByPhone(params.phoneNumber);

    return result.fold((failure) => Left(failure), (delegates) async {
      // 2. تصفية المندوبين بناء على مقارنة الرقم القومي (Password Check)
      //    أو التحقق عبر Firebase Auth للـ admins
      final matched = <Delegate>[];

      for (final delegate in delegates) {
        // Check if this is an admin (marked with __firebase_auth__:email)
        if (delegate.nationalityID.startsWith('__firebase_auth__:')) {
          final email = delegate.nationalityID.replaceFirst(
            '__firebase_auth__:',
            '',
          );

          // Verify password using Firebase Authentication
          final verifyResult = await repository.verifyAdminPassword(
            email,
            params.password,
          );
          final isValid = verifyResult.fold((_) => false, (valid) => valid);

          if (isValid) {
            matched.add(delegate);
          }
        } else {
          // Regular delegate: compare nationalityID with password
          if (delegate.nationalityID == params.password) {
            matched.add(delegate);
          }
        }
      }

      if (matched.isEmpty) {
        return const Left(
          AuthFailure('كلمة المرور غير صحيحة'),
        ); // ❌ الرقم موجود لكن الباسورد غلط
      }

      // إذا كان هناك مندوب واحد فقط وريمامبر مي مفعل، حفظ البيانات
      if (matched.length == 1 && params.rememberMe) {
        await repository.cacheDelegate(matched.first);
      }
      // إذا كانت هناك عدة منظمات، لا نحفظ الآن - سيتم الحفظ بعد اختيار المنظمة

      return Right(matched); // ✅ تطابق! أرجع قائمة المندوبين
    });
  }
}

class LoginParams extends Equatable {
  final String phoneNumber;
  final String password; // الرقم القومي (nationalityID)
  final bool rememberMe;

  const LoginParams({
    required this.phoneNumber,
    required this.password,
    this.rememberMe = false,
  });

  @override
  List<Object> get props => [phoneNumber, password, rememberMe];
}
