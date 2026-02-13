import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';

class Login implements UseCase<User, LoginParams> {
  final AuthRepository repository;

  Login(this.repository);

  @override
  Future<Either<Failure, User>> call(LoginParams params) async {
    return await repository.login(params.mobile, params.motherName);
  }
}

class LoginParams extends Equatable {
  final String mobile;
  final String motherName;

  const LoginParams({required this.mobile, required this.motherName});

  @override
  List<Object> get props => [mobile, motherName];
}
