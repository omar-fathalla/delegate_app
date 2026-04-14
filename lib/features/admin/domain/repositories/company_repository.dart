import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../entities/company.dart';

/// Repository interface for company operations
abstract class CompanyRepository {
  /// Search companies by company code with pagination
  Future<Either<Failure, PaginationResponse<Company>>> searchCompaniesByCode({
    required String organizationUID,
    required String companyCode,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  /// Get all companies with pagination
  Future<Either<Failure, PaginationResponse<Company>>> getCompanies({
    required String organizationUID,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  /// Get company by ID
  Future<Either<Failure, Company>> getCompanyById({
    required String organizationUID,
    required String companyUID,
  });
}
