import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../profile/domain/entities/delegate.dart';
import '../repositories/marketing_search_repository.dart';

/// Use case for searching delegates by name (and optionally by phone)
class SearchDelegateByName
    extends UseCase<PaginationResponse<Delegate>, SearchDelegateByNameParams> {
  final MarketingSearchRepository repository;

  SearchDelegateByName(this.repository);

  @override
  Future<Either<Failure, PaginationResponse<Delegate>>> call(
    SearchDelegateByNameParams params,
  ) async {
    return await repository.searchDelegateByName(
      organizationUID: params.organizationUID,
      name: params.name,
      phoneNumber: params.phoneNumber,
      limit: params.limit,
      startAfterDoc: params.startAfterDoc,
    );
  }
}

/// Parameters for searching delegate by name
class SearchDelegateByNameParams extends Equatable {
  final String organizationUID;
  final String name;
  final String? phoneNumber;
  final int limit;
  final DocumentSnapshot? startAfterDoc;

  const SearchDelegateByNameParams({
    required this.organizationUID,
    required this.name,
    this.phoneNumber,
    this.limit = 20,
    this.startAfterDoc,
  });

  @override
  List<Object?> get props => [
    organizationUID,
    name,
    phoneNumber,
    limit,
    startAfterDoc,
  ];
}
