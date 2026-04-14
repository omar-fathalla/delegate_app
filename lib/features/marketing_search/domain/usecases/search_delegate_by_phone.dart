import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../profile/domain/entities/delegate.dart';
import '../repositories/marketing_search_repository.dart';

/// Use case for searching delegates by phone number
class SearchDelegateByPhone
    extends UseCase<PaginationResponse<Delegate>, SearchDelegateByPhoneParams> {
  final MarketingSearchRepository repository;

  SearchDelegateByPhone(this.repository);

  @override
  Future<Either<Failure, PaginationResponse<Delegate>>> call(
    SearchDelegateByPhoneParams params,
  ) async {
    return await repository.searchDelegateByPhone(
      organizationUID: params.organizationUID,
      phoneNumber: params.phoneNumber,
      limit: params.limit,
      startAfterDoc: params.startAfterDoc,
    );
  }
}

/// Parameters for searching delegate by phone number
class SearchDelegateByPhoneParams extends Equatable {
  final String organizationUID;
  final String phoneNumber;
  final int limit;
  final DocumentSnapshot? startAfterDoc;

  const SearchDelegateByPhoneParams({
    required this.organizationUID,
    required this.phoneNumber,
    this.limit = 20,
    this.startAfterDoc,
  });

  @override
  List<Object?> get props => [
    organizationUID,
    phoneNumber,
    limit,
    startAfterDoc,
  ];
}
