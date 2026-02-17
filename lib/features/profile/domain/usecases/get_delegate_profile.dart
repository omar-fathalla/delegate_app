import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart'; // Check if this exists
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:equatable/equatable.dart';

class GetDelegateProfile
    implements UseCase<Delegate, GetDelegateProfileParams> {
  final ProfileRepository repository;

  GetDelegateProfile(this.repository);

  @override
  Future<Either<Failure, Delegate>> call(
    GetDelegateProfileParams params,
  ) async {
    return await repository.getDelegateProfile(params.uid);
  }
}

class GetDelegateProfileParams extends Equatable {
  final String uid;

  const GetDelegateProfileParams({required this.uid});

  @override
  List<Object> get props => [uid];
}
