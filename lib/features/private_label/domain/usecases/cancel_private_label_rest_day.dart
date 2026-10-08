import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class CancelRestDayParams {
  final String organizationUID;
  final String delegateUid;

  /// `yyyy-MM-dd`
  final String date;

  const CancelRestDayParams({
    required this.organizationUID,
    required this.delegateUid,
    required this.date,
  });
}

class CancelPrivateLabelRestDay implements UseCase<Unit, CancelRestDayParams> {
  final PrivateLabelRepository repository;

  CancelPrivateLabelRestDay(this.repository);

  @override
  Future<Either<Failure, Unit>> call(CancelRestDayParams params) {
    return repository.cancelRestDay(
      organizationUID: params.organizationUID,
      delegateUid: params.delegateUid,
      date: params.date,
    );
  }
}
