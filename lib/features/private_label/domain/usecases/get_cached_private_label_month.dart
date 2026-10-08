import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_month_data.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_month.dart';

class GetCachedPrivateLabelMonth
    implements UseCase<PrivateLabelMonthData?, PrivateLabelMonthParams> {
  final PrivateLabelRepository repository;

  GetCachedPrivateLabelMonth(this.repository);

  @override
  Future<Either<Failure, PrivateLabelMonthData?>> call(
    PrivateLabelMonthParams params,
  ) {
    return repository.getCachedMonth(
      organizationUID: params.organizationUID,
      delegateUid: params.delegateUid,
      year: params.year,
      month: params.month,
    );
  }
}
