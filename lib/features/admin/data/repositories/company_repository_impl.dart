import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import '../datasources/company_remote_datasource.dart';

/// Implementation of CompanyRepository
class CompanyRepositoryImpl implements CompanyRepository {
  final CompanyRemoteDataSource remoteDataSource;

  CompanyRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, PaginationResponse<Company>>> searchCompaniesByCode({
    required String organizationUID,
    required String companyCode,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      final result = await remoteDataSource.searchCompaniesByCode(
        organizationUID: organizationUID,
        companyCode: companyCode,
        lastDocument: lastDocument,
        limit: limit,
      );

      return Right(
        PaginationResponse<Company>(
          items: result.items,
          hasReachedMax: result.hasReachedMax,
          lastDoc: result.lastDoc,
        ),
      );
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ غير متوقع: $e'));
    }
  }

  @override
  Future<Either<Failure, PaginationResponse<Company>>> getCompanies({
    required String organizationUID,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      final result = await remoteDataSource.getCompanies(
        organizationUID: organizationUID,
        lastDocument: lastDocument,
        limit: limit,
      );

      return Right(
        PaginationResponse<Company>(
          items: result.items,
          hasReachedMax: result.hasReachedMax,
          lastDoc: result.lastDoc,
        ),
      );
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ غير متوقع: $e'));
    }
  }

  @override
  Future<Either<Failure, Company>> getCompanyById({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      final result = await remoteDataSource.getCompanyById(
        organizationUID: organizationUID,
        companyUID: companyUID,
      );

      return Right(result);
    } on FirebaseException catch (e) {
      return Left(ServerFailure(_mapFirebaseError(e)));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ غير متوقع: $e'));
    }
  }

  /// Map Firebase errors to user-friendly messages
  String _mapFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية للوصول إلى هذه البيانات';
      case 'not-found':
        return 'الشركة غير موجودة';
      case 'unavailable':
        return 'الخدمة غير متاحة حالياً، يرجى المحاولة لاحقاً';
      case 'deadline-exceeded':
        return 'انتهت مهلة الاتصال، يرجى المحاولة مرة أخرى';
      default:
        return 'حدث خطأ في الاتصال: ${e.message}';
    }
  }
}
