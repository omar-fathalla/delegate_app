import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class RegisterRestDayParams {
  final String organizationUID;
  final String companyUID;
  final String delegateUid;
  final String delegateName;

  /// `yyyy-MM-dd`
  final String date;
  final int restAllowance;

  const RegisterRestDayParams({
    required this.organizationUID,
    required this.companyUID,
    required this.delegateUid,
    required this.delegateName,
    required this.date,
    required this.restAllowance,
  });
}

class RegisterPrivateLabelRestDay
    implements UseCase<PrivateLabelDay, RegisterRestDayParams> {
  final PrivateLabelRepository repository;

  RegisterPrivateLabelRestDay(this.repository);

  @override
  Future<Either<Failure, PrivateLabelDay>> call(RegisterRestDayParams params) {
    return repository.registerRestDay(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      delegateUid: params.delegateUid,
      delegateName: params.delegateName,
      date: params.date,
      restAllowance: params.restAllowance,
    );
  }
}
