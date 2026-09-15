import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';

abstract class DelegateSubscriptionRepository {
  /// Submits a new delegate subscription request with file uploads
  Future<Either<Failure, String>> submitSubscriptionRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required String companyUID,
    required String companyName,
    required String organizationUID,
    required String organizationName,
    required String firstName,
    required String secondName,
    required String thirdName,
    required String phoneNumber,
    required String nationalId,
    required File profileImage,
    required File nationalIdFront,
    required File nationalIdBack,
    required SubscriptionPaymentMethod paymentMethod,
    String? receiptCode,
    File? receiptImage,
    double? fee,
    int? remainingMonths,
  });

  /// Streams subscription requests filtered by status or organization/company
  Stream<List<DelegateSubscriptionRequest>> getSubscriptionRequestsStream({
    SubscriptionRequestStatus? statusFilter,
    String? organizationUID,
    String? companyUID,
  });

  /// Approves a subscription request, creating/activating the delegate
  Future<Either<Failure, void>> approveSubscriptionRequest({
    required DelegateSubscriptionRequest request,
    required String reviewerUid,
    required String reviewerName,
  });

  /// Rejects a subscription request with a stated reason
  Future<Either<Failure, void>> rejectSubscriptionRequest({
    required DelegateSubscriptionRequest request,
    required String reason,
    required String reviewerUid,
    required String reviewerName,
  });
}
