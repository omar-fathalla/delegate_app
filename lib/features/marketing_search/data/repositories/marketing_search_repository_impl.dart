import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../admin/domain/entities/company.dart';
import '../../../profile/domain/entities/delegate.dart';
import '../../domain/repositories/marketing_search_repository.dart';
import '../datasources/marketing_search_remote_datasource.dart';

/// Implementation of MarketingSearchRepository
class MarketingSearchRepositoryImpl implements MarketingSearchRepository {
  final MarketingSearchRemoteDataSource remoteDataSource;

  MarketingSearchRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, PaginationResponse<Company>>> searchCompanyByName({
    required String organizationUID,
    required String companyName,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      final result = await remoteDataSource.searchCompanyByName(
        organizationUID: organizationUID,
        companyName: companyName,
        limit: limit,
        startAfterDoc: startAfterDoc,
      );

      return Right(result);
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ غير متوقع أثناء البحث عن الشركة: $e'));
    }
  }

  @override
  Future<Either<Failure, PaginationResponse<Delegate>>> searchDelegateByPhone({
    required String organizationUID,
    required String phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      final result = await remoteDataSource.searchDelegateByPhone(
        organizationUID: organizationUID,
        phoneNumber: phoneNumber,
        limit: limit,
        startAfterDoc: startAfterDoc,
      );

      return Right(result);
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      return Left(
        ServerFailure('حدث خطأ غير متوقع أثناء البحث عن المندوب برقم الموبايل'),
      );
    }
  }

  @override
  Future<Either<Failure, PaginationResponse<Delegate>>> searchDelegateByName({
    required String organizationUID,
    required String name,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      final result = await remoteDataSource.searchDelegateByName(
        organizationUID: organizationUID,
        name: name,
        phoneNumber: phoneNumber,
        limit: limit,
        startAfterDoc: startAfterDoc,
      );

      return Right(result);
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      // TAS-270: the message names the search actually run (name, or
      // name + phone), never the raw exception.
      final withPhone = phoneNumber != null && phoneNumber.trim().isNotEmpty;
      return Left(
        ServerFailure(
          withPhone
              ? 'حدث خطأ غير متوقع أثناء البحث عن المندوب بالاسم ورقم الموبايل'
              : 'حدث خطأ غير متوقع أثناء البحث عن المندوب بالاسم',
        ),
      );
    }
  }

  /// Map Firebase errors to user-friendly messages
  String _mapFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية للوصول إلى هذه البيانات';
      case 'not-found':
        return 'البيانات المطلوبة غير موجودة';
      case 'unavailable':
        return 'الخدمة غير متاحة حالياً، يرجى المحاولة لاحقاً';
      default:
        return 'حدث خطأ في الاتصال بقاعدة البيانات';
    }
  }
}
