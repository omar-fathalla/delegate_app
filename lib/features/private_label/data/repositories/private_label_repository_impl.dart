import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_local_data_source.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_remote_data_source.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_product_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_month_data.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class PrivateLabelRepositoryImpl implements PrivateLabelRepository {
  final PrivateLabelRemoteDataSource remoteDataSource;
  final PrivateLabelLocalDataSource localDataSource;

  /// Prevents two overlapping sync loops (connectivity event + manual refresh).
  bool _isSyncing = false;

  PrivateLabelRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  Failure _toFailure(Object e, String fallback) {
    if (e is Failure) return e;
    return ServerFailure(fallback);
  }

  @override
  Future<Either<Failure, PrivateLabelMonthData?>> getCachedMonth({
    required String organizationUID,
    required String delegateUid,
    required int year,
    required int month,
  }) async {
    try {
      final cached = localDataSource.getCachedMonth(
        organizationUID,
        delegateUid,
        PrivateLabelDates.monthKey(year, month),
      );
      if (cached == null) return const Right(null);
      return Right(PrivateLabelMonthData(
        year: year,
        month: month,
        days: cached.days,
        restAllowance: cached.restAllowance,
      ));
    } catch (_) {
      return const Left(CacheFailure('تعذر قراءة البيانات المحفوظة.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelMonthData>> getMonth({
    required String organizationUID,
    required String delegateUid,
    required int year,
    required int month,
  }) async {
    try {
      final monthKey = PrivateLabelDates.monthKey(year, month);
      final days = await remoteDataSource.getMonthDays(
        organizationUID: organizationUID,
        delegateUid: delegateUid,
        monthKey: monthKey,
      );
      final allowance = await remoteDataSource.getRestAllowance(organizationUID);

      await localDataSource.cacheMonth(
        organizationUID,
        delegateUid,
        monthKey,
        days,
        allowance,
      );

      return Right(PrivateLabelMonthData(
        year: year,
        month: month,
        days: days,
        restAllowance: allowance,
      ));
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تحميل بيانات الشهر.'));
    }
  }

  @override
  Future<Either<Failure, List<PrivateLabelDay>>> getOrganizationMonthDays({
    required String organizationUID,
    required String monthKey,
    String? companyUID,
  }) async {
    try {
      final days = await remoteDataSource.getOrganizationMonthDays(
        organizationUID: organizationUID,
        monthKey: monthKey,
        companyUID: companyUID,
      );
      return Right(days);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تحميل أيام الشهر للمنظمة.'));
    }
  }

  @override
  Future<Either<Failure, int>> getRestAllowance(String organizationUID) async {
    try {
      final allowance = await remoteDataSource.getRestAllowance(organizationUID);
      return Right(allowance);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تحميل رصيد الإجازات.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelSubmitResult>> submitAudit(
    PrivateLabelAuditDraft draft,
  ) async {
    PrivateLabelAuditDraft saved;
    try {
      final productPath = await localDataSource.persistImage(
        draft.productImagePath,
        '${draft.id}_product.jpg',
      );
      final pricePath = await localDataSource.persistImage(
        draft.priceImagePath,
        '${draft.id}_price.jpg',
      );
      saved = draft.copyWith(productImagePath: productPath, priceImagePath: pricePath);
      await localDataSource.addPendingDraft(saved);
    } catch (_) {
      return const Left(CacheFailure('تعذر حفظ التوثيق على الموبايل. حاول تاني.'));
    }

    // Offline-first: the audit is safe locally; uploading is best-effort.
    try {
      await remoteDataSource.syncAudit(saved);
      await _cleanupDraft(saved);
      return Right(PrivateLabelSubmitResult(draft: saved, synced: true));
    } catch (_) {
      return Right(PrivateLabelSubmitResult(draft: saved, synced: false));
    }
  }

  Future<void> _cleanupDraft(PrivateLabelAuditDraft draft) async {
    await localDataSource.removePendingDraft(draft.id);
    await localDataSource.deleteImage(draft.productImagePath);
    await localDataSource.deleteImage(draft.priceImagePath);
  }

  @override
  Future<Either<Failure, int>> syncPendingAudits(String delegateUid) async {
    if (_isSyncing) return const Right(0);
    _isSyncing = true;
    var synced = 0;
    try {
      final pending = localDataSource.getPendingDrafts(delegateUid);
      for (final draft in pending) {
        try {
          await remoteDataSource.syncAudit(draft);
          await _cleanupDraft(draft);
          synced++;
        } catch (e) {
          // Most likely still offline: stop and retry on the next trigger.
          if (synced == 0) {
            return Left(_toFailure(e, 'لسه مفيش اتصال لرفع التوثيقات.'));
          }
          break;
        }
      }
      return Right(synced);
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<Either<Failure, List<PrivateLabelAuditDraft>>> getPendingAudits(
    String delegateUid,
  ) async {
    try {
      return Right(localDataSource.getPendingDrafts(delegateUid));
    } catch (_) {
      return const Left(CacheFailure('تعذر قراءة التوثيقات المحفوظة.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelDay>> registerRestDay({
    required String organizationUID,
    required String companyUID,
    required String delegateUid,
    required String delegateName,
    required String date,
    required int restAllowance,
  }) async {
    // A day with locally queued audits is a worked day, not a rest day.
    final hasPendingThatDay =
        localDataSource.getPendingDrafts(delegateUid).any((d) => d.auditDate == date);
    if (hasPendingThatDay) {
      return const Left(ServerFailure('اليوم ده فيه توثيق محفوظ، فمينفعش يتسجل إجازة.'));
    }
    try {
      final day = await remoteDataSource.registerRestDay(
        organizationUID: organizationUID,
        companyUID: companyUID,
        delegateUid: delegateUid,
        delegateName: delegateName,
        date: date,
        restAllowance: restAllowance,
      );
      return Right(day);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تسجيل الإجازة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> cancelRestDay({
    required String organizationUID,
    required String delegateUid,
    required String date,
  }) async {
    try {
      await remoteDataSource.cancelRestDay(
        organizationUID: organizationUID,
        delegateUid: delegateUid,
        date: date,
      );
      return const Right(unit);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في إلغاء الإجازة.'));
    }
  }

  @override
  Future<Either<Failure, List<PrivateLabelAudit>>> getAudits({
    required String organizationUID,
    String? date,
    String? delegateUid,
    String? companyUID,
  }) async {
    try {
      final list = await remoteDataSource.getAudits(
        organizationUID: organizationUID,
        date: date,
        delegateUid: delegateUid,
        companyUID: companyUID,
      );
      return Right(list);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تحميل التوثيقات.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelAudit>> reviewAudit({
    required String organizationUID,
    required String auditId,
    required PrivateLabelReviewStatus status,
    required String reviewerUid,
    required String reviewerName,
    String? notes,
  }) async {
    try {
      final audit = await remoteDataSource.reviewAudit(
        organizationUID: organizationUID,
        auditId: auditId,
        status: status,
        reviewerUid: reviewerUid,
        reviewerName: reviewerName,
        notes: notes,
      );
      return Right(audit);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في حفظ قرار المراجعة.'));
    }
  }

  @override
  Future<Either<Failure, List<PrivateLabelProduct>>> getProducts(
    String organizationUID,
  ) async {
    try {
      final products = await remoteDataSource.getProducts(organizationUID);
      await localDataSource.cacheProducts(organizationUID, products);
      return Right(products);
    } catch (e) {
      final cached = localDataSource.getCachedProducts(organizationUID);
      if (cached.isNotEmpty) return Right(cached);
      return Left(_toFailure(e, 'فشل في تحميل كتالوج المنتجات.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelProduct>> saveProduct(
    PrivateLabelProduct product,
  ) async {
    try {
      final saved = await remoteDataSource.saveProduct(
        PrivateLabelProductModel.fromEntity(product),
      );
      return Right(saved);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في حفظ المنتج.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteAudit({
    required String organizationUID,
    required String auditId,
    required String delegateUid,
    required String date,
  }) async {
    try {
      await remoteDataSource.deleteAudit(
        organizationUID: organizationUID,
        auditId: auditId,
        delegateUid: delegateUid,
        date: date,
      );
      return const Right(unit);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في حذف التوثيق.'));
    }
  }

  @override
  Future<Either<Failure, PrivateLabelAudit>> updateAudit({
    required String organizationUID,
    required String auditId,
    required String productName,
    String? productId,
    double? referencePrice,
    required double shelfPrice,
    required PrivateLabelStockStatus stockStatus,
    String? barcode,
    String? notes,
  }) async {
    try {
      final updated = await remoteDataSource.updateAudit(
        organizationUID: organizationUID,
        auditId: auditId,
        productName: productName,
        productId: productId,
        referencePrice: referencePrice,
        shelfPrice: shelfPrice,
        stockStatus: stockStatus,
        barcode: barcode,
        notes: notes,
      );
      return Right(updated);
    } catch (e) {
      return Left(_toFailure(e, 'فشل في تعديل التوثيق.'));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getBranches(String organizationUID) async {
    try {
      final branches = await remoteDataSource.getBranches(organizationUID);
      await localDataSource.cacheBranches(organizationUID, branches);
      return Right(branches);
    } catch (e) {
      final cached = localDataSource.getCachedBranches(organizationUID);
      if (cached.isNotEmpty) return Right(cached);
      return Left(_toFailure(e, 'فشل في تحميل الفروع.'));
    }
  }
}
