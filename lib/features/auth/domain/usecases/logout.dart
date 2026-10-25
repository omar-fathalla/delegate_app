import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:equatable/equatable.dart';

class LogoutParams extends Equatable {
  final String? userId;

  const LogoutParams({this.userId});

  @override
  List<Object?> get props => [userId];
}

class Logout implements UseCase<void, LogoutParams> {
  final AuthRepository repository;

  Logout(this.repository);

  @override
  Future<Either<Failure, void>> call(LogoutParams params) {
    return repository.logout(userId: params.userId);
  }
}
