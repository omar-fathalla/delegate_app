import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/features/changelog/domain/repositories/changelog_repository.dart';

/// Use case that fetches only the updates the user hasn't seen.
class GetNewUpdates extends UseCase<List<AppUpdate>, NoParams> {
  final ChangelogRepository repository;

  GetNewUpdates(this.repository);

  @override
  Future<Either<Failure, List<AppUpdate>>> call(NoParams params) {
    return repository.getNewUpdates();
  }
}
