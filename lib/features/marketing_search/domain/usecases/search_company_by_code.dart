import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../admin/domain/entities/company.dart';
import '../repositories/marketing_search_repository.dart';

/// Use case for searching companies by name
class SearchCompanyByCode
    extends UseCase<PaginationResponse<Company>, SearchCompanyByCodeParams> {
  final MarketingSearchRepository repository;

  SearchCompanyByCode(this.repository);

  @override
  Future<Either<Failure, PaginationResponse<Company>>> call(
    SearchCompanyByCodeParams params,
  ) async {
    return await repository.searchCompanyByName(
      organizationUID: params.organizationUID,
      companyName: params.companyName,
      limit: params.limit,
      startAfterDoc: params.startAfterDoc,
    );
  }
}

/// Parameters for searching company by name
class SearchCompanyByCodeParams extends Equatable {
  final String organizationUID;
  final String companyName;
  final int limit;
  final DocumentSnapshot? startAfterDoc;

  const SearchCompanyByCodeParams({
    required this.organizationUID,
    required this.companyName,
    this.limit = 20,
    this.startAfterDoc,
  });

  @override
  List<Object?> get props => [
    organizationUID,
    companyName,
    limit,
    startAfterDoc,
  ];
}
