import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class Login implements UseCase<Delegate, LoginParams> {
  final AuthRepository repository;

  Login(this.repository);

  @override
  Future<Either<Failure, Delegate>> call(LoginParams params) async {
    // 1. جلب بيانات المندوب من السيرفر بناء على رقم الهاتف
    final result = await repository.getDelegateByPhone(params.phoneNumber);

    return result.fold((failure) => Left(failure), (delegate) async {
      // 2. مقارنة الباسورد المدخل مع الرقم القومي (Local Check)
      if (delegate.nationalityID == params.password) {
        // 3. حفظ البيانات محلياً إذا اختار "تذكرني"
        if (params.rememberMe) {
          await repository.cacheDelegate(delegate);
        }
        return Right(delegate); // ✅ تطابق! تم الدخول
      } else {
        return const Left(
          AuthFailure('كلمة المرور غير صحيحة'),
        ); // ❌ الرقم موجود لكن الباسورد غلط
      }
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
