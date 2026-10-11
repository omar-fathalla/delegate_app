import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

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

  /// Submits a request to link an existing registered delegate to an additional organization
  Future<Either<Failure, String>> submitAddOrganizationRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required String companyUID,
    required String companyName,
    required String targetOrganizationUID,
    required String targetOrganizationName,
    required Delegate existingDelegate,
    required SubscriptionPaymentMethod paymentMethod,
    String? receiptCode,
    File? receiptImage,
    double? fee,
    int? remainingMonths,
  });

  /// Submits a request by a company supervisor to delete a non-Fathalla delegate
  Future<Either<Failure, String>> submitDeleteDelegateRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required Delegate delegate,
    required String reason,
  });

  /// Checks whether a 5-digit receipt code is already used across the system
  Future<Either<Failure, bool>> isReceiptCodeUsed(String receiptCode);

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
