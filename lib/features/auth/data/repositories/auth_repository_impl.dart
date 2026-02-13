import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, User>> login(String mobile, String motherName) async {
    try {
      final user = await remoteDataSource.login(mobile, motherName);
      return Right(user);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }
}
