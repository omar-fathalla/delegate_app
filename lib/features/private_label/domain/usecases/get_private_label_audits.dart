import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class GetPrivateLabelAuditsParams {
  final String organizationUID;

  /// `yyyy-MM-dd` (optional, null to fetch across all dates)
  final String? date;
  final String? delegateUid;
  final String? companyUID;

  const GetPrivateLabelAuditsParams({
    required this.organizationUID,
    this.date,
    this.delegateUid,
    this.companyUID,
  });
}

class GetPrivateLabelAudits
    implements UseCase<List<PrivateLabelAudit>, GetPrivateLabelAuditsParams> {
  final PrivateLabelRepository repository;

  GetPrivateLabelAudits(this.repository);

  @override
  Future<Either<Failure, List<PrivateLabelAudit>>> call(
    GetPrivateLabelAuditsParams params,
  ) {
    return repository.getAudits(
      organizationUID: params.organizationUID,
      date: params.date,
      delegateUid: params.delegateUid,
      companyUID: params.companyUID,
    );
  }
}
