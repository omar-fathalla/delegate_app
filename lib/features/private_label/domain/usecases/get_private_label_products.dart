import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

/// Params: organization UID.
class GetPrivateLabelProducts
    implements UseCase<List<PrivateLabelProduct>, String> {
  final PrivateLabelRepository repository;

  GetPrivateLabelProducts(this.repository);

  @override
  Future<Either<Failure, List<PrivateLabelProduct>>> call(String organizationUID) {
    return repository.getProducts(organizationUID);
  }
}
