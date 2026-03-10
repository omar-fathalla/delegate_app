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
    // 0. Hardcoded Admin Check (حالة استثنائية ثابتة للمدير العام)
    if (params.phoneNumber == '01508899965' && params.password == '4816361Aa') {
      final systemAdmin = Delegate(
        uid: 'system-admin-hardcoded',
        firstName: 'System',
        middleName: '',
        lastName: 'Admin',
        fullName: 'System Admin',
        nationalityID: '4816361Aa',
        motherName: '',
        city: '',
        phoneNumber: '01508899965',
        gender: DelegateGender.male,
        position: DelegatePosition.supervisor, // لفتح لوحة التحكم فوراً
        birthDate: DateTime.now(),
        organizationUID: '',
        organizationName: '',
        companyUID: '',
        companyName: '',
        status: DelegateStatus.approved,
        delegatePublicId: '',
        allReceiptCodes: const [],
        createdAt: DateTime.now(),
        createdBy: 'system_admin',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
      );

      if (params.rememberMe) {
        await repository.cacheDelegate(systemAdmin);
      }
      return Right(systemAdmin);
    }

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
