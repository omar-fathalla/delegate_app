import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_month_data.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class PrivateLabelMonthParams {
  final String organizationUID;
  final String delegateUid;
  final int year;
  final int month;

  const PrivateLabelMonthParams({
    required this.organizationUID,
    required this.delegateUid,
    required this.year,
    required this.month,
  });
}

class GetPrivateLabelMonth
    implements UseCase<PrivateLabelMonthData, PrivateLabelMonthParams> {
  final PrivateLabelRepository repository;

  GetPrivateLabelMonth(this.repository);

  @override
  Future<Either<Failure, PrivateLabelMonthData>> call(
    PrivateLabelMonthParams params,
  ) {
    return repository.getMonth(
      organizationUID: params.organizationUID,
      delegateUid: params.delegateUid,
      year: params.year,
      month: params.month,
    );
  }
}
