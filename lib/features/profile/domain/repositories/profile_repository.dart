import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class ProfileRepository {
  Future<Either<Failure, Delegate>> getDelegateProfile(String uid);
}
