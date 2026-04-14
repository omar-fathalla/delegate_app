import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/models/pagination_response.dart';
import '../../../admin/domain/entities/company.dart';
import '../../../profile/domain/entities/delegate.dart';

/// Repository interface for marketing search operations
abstract class MarketingSearchRepository {
  /// Search for a company by its name
  /// Returns a paginated list of companies matching the name
  /// [startAfterDoc] is used for pagination - pass the last document from previous batch
  Future<Either<Failure, PaginationResponse<Company>>> searchCompanyByName({
    required String organizationUID,
    required String companyName,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  });

  /// Search for a delegate by phone number
  /// Returns a paginated list of delegates matching the phone number
  /// [startAfterDoc] is used for pagination - pass the last document from previous batch
  Future<Either<Failure, PaginationResponse<Delegate>>> searchDelegateByPhone({
    required String organizationUID,
    required String phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  });
}
