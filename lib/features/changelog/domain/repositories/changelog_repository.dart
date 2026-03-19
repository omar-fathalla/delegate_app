import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';

/// Repository interface for fetching app updates.
abstract class ChangelogRepository {
  /// Fetches all active updates from the remote data source.
  Future<Either<Failure, List<AppUpdate>>> getUpdates();

  /// Fetches only the updates the user hasn't seen yet, based on
  /// the last-seen timestamp stored locally.
  Future<Either<Failure, List<AppUpdate>>> getNewUpdates();
}
