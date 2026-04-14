import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/company.dart';
import '../repositories/company_repository.dart';

/// Use case for searching companies by company code with pagination
class SearchCompaniesByCode
    extends UseCase<PaginationResponse<Company>, SearchCompaniesByCodeParams> {
  final CompanyRepository repository;

  SearchCompaniesByCode(this.repository);

  @override
  Future<Either<Failure, PaginationResponse<Company>>> call(
    SearchCompaniesByCodeParams params,
  ) {
    return repository.searchCompaniesByCode(
      organizationUID: params.organizationUID,
      companyCode: params.companyCode,
      lastDocument: params.lastDocument,
      limit: params.limit,
    );
  }
}

class SearchCompaniesByCodeParams extends Equatable {
  final String organizationUID;
  final String companyCode;
  final DocumentSnapshot? lastDocument;
  final int limit;

  const SearchCompaniesByCodeParams({
    required this.organizationUID,
    required this.companyCode,
    this.lastDocument,
    this.limit = 20,
  });

  @override
  List<Object?> get props => [
    organizationUID,
    companyCode,
    lastDocument,
    limit,
  ];
}
