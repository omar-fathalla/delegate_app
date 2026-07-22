import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/captured_photo.dart';
import '../repositories/photo_permission_repository.dart';

class GetDelegateCapturedPhotos implements UseCase<List<CapturedPhoto>, GetDelegateCapturedPhotosParams> {
  final PhotoPermissionRepository repository;

  GetDelegateCapturedPhotos(this.repository);

  @override
  Future<Either<Failure, List<CapturedPhoto>>> call(GetDelegateCapturedPhotosParams params) {
    return repository.getDelegateCapturedPhotos(
      delegateUID: params.delegateUID,
    );
  }
}

class GetDelegateCapturedPhotosParams extends Equatable {
  final String delegateUID;

  const GetDelegateCapturedPhotosParams({
    required this.delegateUID,
  });

  @override
  List<Object?> get props => [delegateUID];
}
