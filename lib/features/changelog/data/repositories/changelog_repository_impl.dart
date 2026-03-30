import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/changelog/data/datasources/changelog_remote_datasource.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/features/changelog/domain/repositories/changelog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChangelogRepositoryImpl implements ChangelogRepository {
  final ChangelogRemoteDataSource remoteDataSource;
  final SharedPreferences sharedPreferences;

  /// Key used to store the last-seen timestamp in SharedPreferences.
  static const _lastSeenKey = 'changelog_last_seen';

  ChangelogRepositoryImpl({
    required this.remoteDataSource,
    required this.sharedPreferences,
  });

  @override
  Future<Either<Failure, List<AppUpdate>>> getUpdates() async {
    try {
      final updates = await remoteDataSource.getUpdates();
      // Mark all as seen when viewing the full changelog
      await _markAllAsSeen();
      return Right(updates);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء جلب التحديثات.'),
      );
    }
  }

  @override
  Future<Either<Failure, List<AppUpdate>>> getNewUpdates() async {
    try {
      final lastSeenMs = sharedPreferences.getInt(_lastSeenKey);
      final since = lastSeenMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
          : DateTime(2020); // Default: show all if never seen

      final updates = await remoteDataSource.getUpdatesSince(since);
      return Right(updates);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء جلب التحديثات الجديدة.'),
      );
    }
  }

  /// Marks all updates as seen by storing the current timestamp.
  Future<void> _markAllAsSeen() async {
    await sharedPreferences.setInt(
      _lastSeenKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
