import 'package:equatable/equatable.dart';

enum SubscriptionPaymentMethod { companyDeduction, receipt }

enum SubscriptionRequestStatus { pending, approved, rejected }

class DelegateSubscriptionRequest extends Equatable {
  final String id;
  final String supervisorUid;
  final String supervisorName;
  final String supervisorPhone;
  final String companyUID;
  final String companyName;
  final String organizationUID;
  final String organizationName;
  final String firstName;
  final String secondName;
  final String thirdName;
  final String fullName;
  final String phoneNumber;
  final String nationalId;
  final String profileImageUrl;
  final String nationalIdFrontUrl;
  final String nationalIdBackUrl;
  final SubscriptionPaymentMethod paymentMethod;
  final String? receiptCode;
  final String? receiptImageUrl;
  final String subscriptionCycle;
  final DateTime cycleStartDate;
  final DateTime cycleEndDate;
  final double fee;
  final int remainingMonths;
  final SubscriptionRequestStatus status;
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const DelegateSubscriptionRequest({
    required this.id,
    required this.supervisorUid,
    required this.supervisorName,
    required this.supervisorPhone,
    required this.companyUID,
    required this.companyName,
    required this.organizationUID,
    required this.organizationName,
    required this.firstName,
    required this.secondName,
    required this.thirdName,
    required this.fullName,
    required this.phoneNumber,
    required this.nationalId,
    required this.profileImageUrl,
    required this.nationalIdFrontUrl,
    required this.nationalIdBackUrl,
    required this.paymentMethod,
    this.receiptCode,
    this.receiptImageUrl,
    required this.subscriptionCycle,
    required this.cycleStartDate,
    required this.cycleEndDate,
    this.fee = 500.0,
    this.remainingMonths = 6,
    this.status = SubscriptionRequestStatus.pending,
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supervisorUid': supervisorUid,
      'supervisorName': supervisorName,
      'supervisorPhone': supervisorPhone,
      'companyUID': companyUID,
      'companyName': companyName,
      'organizationUID': organizationUID,
      'organizationName': organizationName,
      'firstName': firstName,
      'secondName': secondName,
      'thirdName': thirdName,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'nationalId': nationalId,
      'profileImageUrl': profileImageUrl,
      'nationalIdFrontUrl': nationalIdFrontUrl,
      'nationalIdBackUrl': nationalIdBackUrl,
      'paymentMethod': paymentMethod == SubscriptionPaymentMethod.companyDeduction
          ? 'company_deduction'
          : 'receipt',
      'receiptCode': receiptCode,
      'receiptImageUrl': receiptImageUrl,
      'subscriptionCycle': subscriptionCycle,
      'cycleStartDate': cycleStartDate.toIso8601String(),
      'cycleEndDate': cycleEndDate.toIso8601String(),
      'fee': fee,
      'remainingMonths': remainingMonths,
      'status': status.name,
      'rejectionReason': rejectionReason,
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DelegateSubscriptionRequest.fromMap(Map<String, dynamic> map, String docId) {
    SubscriptionPaymentMethod parsePaymentMethod(dynamic val) {
      if (val == 'company_deduction') return SubscriptionPaymentMethod.companyDeduction;
      return SubscriptionPaymentMethod.receipt;
    }

    SubscriptionRequestStatus parseStatus(dynamic val) {
      if (val == 'approved') return SubscriptionRequestStatus.approved;
      if (val == 'rejected') return SubscriptionRequestStatus.rejected;
      return SubscriptionRequestStatus.pending;
    }

    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      try {
        return (val as dynamic).toDate();
      } catch (_) {
        return DateTime.now();
      }
    }

    return DelegateSubscriptionRequest(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      supervisorUid: map['supervisorUid'] ?? '',
      supervisorName: map['supervisorName'] ?? '',
      supervisorPhone: map['supervisorPhone'] ?? '',
      companyUID: map['companyUID'] ?? '',
      companyName: map['companyName'] ?? '',
      organizationUID: map['organizationUID'] ?? '',
      organizationName: map['organizationName'] ?? '',
      firstName: map['firstName'] ?? '',
      secondName: map['secondName'] ?? '',
      thirdName: map['thirdName'] ?? '',
      fullName: map['fullName'] ??
          '${map['firstName'] ?? ''} ${map['secondName'] ?? ''} ${map['thirdName'] ?? ''}'
              .trim(),
      phoneNumber: map['phoneNumber'] ?? '',
      nationalId: map['nationalId'] ?? '',
      profileImageUrl: map['profileImageUrl'] ?? '',
      nationalIdFrontUrl: map['nationalIdFrontUrl'] ?? '',
      nationalIdBackUrl: map['nationalIdBackUrl'] ?? '',
      paymentMethod: parsePaymentMethod(map['paymentMethod']),
      receiptCode: map['receiptCode'],
      receiptImageUrl: map['receiptImageUrl'],
      subscriptionCycle: map['subscriptionCycle'] ?? '',
      cycleStartDate: parseDate(map['cycleStartDate']),
      cycleEndDate: parseDate(map['cycleEndDate']),
      fee: (map['fee'] as num?)?.toDouble() ?? 500.0,
      remainingMonths: (map['remainingMonths'] as num?)?.toInt() ?? 6,
      status: parseStatus(map['status']),
      rejectionReason: map['rejectionReason'],
      reviewedBy: map['reviewedBy'],
      reviewedAt: map['reviewedAt'] != null ? parseDate(map['reviewedAt']) : null,
      createdAt: parseDate(map['createdAt']),
    );
  }

  DelegateSubscriptionRequest copyWith({
    String? id,
    String? supervisorUid,
    String? supervisorName,
    String? supervisorPhone,
    String? companyUID,
    String? companyName,
    String? organizationUID,
    String? organizationName,
    String? firstName,
    String? secondName,
    String? thirdName,
    String? fullName,
    String? phoneNumber,
    String? nationalId,
    String? profileImageUrl,
    String? nationalIdFrontUrl,
    String? nationalIdBackUrl,
    SubscriptionPaymentMethod? paymentMethod,
    String? receiptCode,
    String? receiptImageUrl,
    String? subscriptionCycle,
    DateTime? cycleStartDate,
    DateTime? cycleEndDate,
    double? fee,
    int? remainingMonths,
    SubscriptionRequestStatus? status,
    String? rejectionReason,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
  }) {
    return DelegateSubscriptionRequest(
      id: id ?? this.id,
      supervisorUid: supervisorUid ?? this.supervisorUid,
      supervisorName: supervisorName ?? this.supervisorName,
      supervisorPhone: supervisorPhone ?? this.supervisorPhone,
      companyUID: companyUID ?? this.companyUID,
      companyName: companyName ?? this.companyName,
      organizationUID: organizationUID ?? this.organizationUID,
      organizationName: organizationName ?? this.organizationName,
      firstName: firstName ?? this.firstName,
      secondName: secondName ?? this.secondName,
      thirdName: thirdName ?? this.thirdName,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      nationalId: nationalId ?? this.nationalId,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      nationalIdFrontUrl: nationalIdFrontUrl ?? this.nationalIdFrontUrl,
      nationalIdBackUrl: nationalIdBackUrl ?? this.nationalIdBackUrl,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      receiptCode: receiptCode ?? this.receiptCode,
      receiptImageUrl: receiptImageUrl ?? this.receiptImageUrl,
      subscriptionCycle: subscriptionCycle ?? this.subscriptionCycle,
      cycleStartDate: cycleStartDate ?? this.cycleStartDate,
      cycleEndDate: cycleEndDate ?? this.cycleEndDate,
      fee: fee ?? this.fee,
      remainingMonths: remainingMonths ?? this.remainingMonths,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        supervisorUid,
        companyUID,
        organizationUID,
        phoneNumber,
        nationalId,
        paymentMethod,
        receiptCode,
        subscriptionCycle,
        fee,
        remainingMonths,
        status,
        createdAt,
      ];
}
