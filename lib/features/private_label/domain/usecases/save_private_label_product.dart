import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class SavePrivateLabelProduct
    implements UseCase<PrivateLabelProduct, PrivateLabelProduct> {
  final PrivateLabelRepository repository;

  SavePrivateLabelProduct(this.repository);

  @override
  Future<Either<Failure, PrivateLabelProduct>> call(PrivateLabelProduct params) {
    if (params.name.trim().isEmpty) {
      return Future.value(const Left(ServerFailure('اكتب اسم المنتج.')));
    }
    if (params.referencePrice != null && params.referencePrice! <= 0) {
      return Future.value(const Left(ServerFailure('السعر الرسمي لازم يكون أكبر من صفر.')));
    }
    return repository.saveProduct(params);
  }
}
