import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/models/pagination_response.dart';
import '../entities/company.dart';
import '../repositories/company_repository.dart';

/// Use case for getting companies with pagination
class GetCompanies
    extends UseCase<PaginationResponse<Company>, GetCompaniesParams> {
  final CompanyRepository repository;

  GetCompanies(this.repository);

  @override
  Future<Either<Failure, PaginationResponse<Company>>> call(
    GetCompaniesParams params,
  ) {
    return repository.getCompanies(
      organizationUID: params.organizationUID,
      lastDocument: params.lastDocument,
      limit: params.limit,
    );
  }
}

class GetCompaniesParams extends Equatable {
  final String organizationUID;
  final DocumentSnapshot? lastDocument;
  final int limit;

  const GetCompaniesParams({
    required this.organizationUID,
    this.lastDocument,
    this.limit = 20,
  });

  @override
  List<Object?> get props => [organizationUID, lastDocument, limit];
}
