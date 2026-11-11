import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:equatable/equatable.dart';

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return [for (final e in raw) e.toString().trim()].where((e) => e.isNotEmpty).toList();
}


enum SubscriptionPaymentMethod {
  companyDeduction,
  instaPay,
  branchReceipt,
  freePromotion,
  /// Online payment through Paymob (the only paid method from 2027).
  paymob,
  /// No charge: e.g. adding a chain (one subscription covers all chains).
  notRequired,
}

extension SubscriptionPaymentMethodX on SubscriptionPaymentMethod {
  String get displayName {
    switch (this) {
      case SubscriptionPaymentMethod.companyDeduction:
        return 'خصم من حساب الشركة';
      case SubscriptionPaymentMethod.instaPay:
        return 'تحويل عبر انستاباي (InstaPay)';
      case SubscriptionPaymentMethod.branchReceipt:
        return 'إيصال إلكتروني من تسويق الفرع';
      case SubscriptionPaymentMethod.freePromotion:
        return 'عرض ترويجي مجاني (حتى 31/12)';
      case SubscriptionPaymentMethod.paymob:
        return 'دفع إلكتروني (Paymob)';
      case SubscriptionPaymentMethod.notRequired:
        return 'بدون رسوم (مشمول في اشتراك المندوب)';
    }
  }

  String get shortName {
    switch (this) {
      case SubscriptionPaymentMethod.companyDeduction:
        return 'خصم شركة';
      case SubscriptionPaymentMethod.instaPay:
        return 'انستاباي';
      case SubscriptionPaymentMethod.branchReceipt:
        return 'إيصال إلكتروني';
      case SubscriptionPaymentMethod.freePromotion:
        return 'عرض مجاني';
      case SubscriptionPaymentMethod.paymob:
        return 'Paymob';
      case SubscriptionPaymentMethod.notRequired:
        return 'بدون رسوم';
    }
  }
}

enum SubscriptionRequestStatus { pending, approved, rejected, cancelled, expired }

/// Payment state of a request. Only the server (verified Paymob webhook)
/// may set [paid]; firestore.rules deny it from clients.
enum SubscriptionPaymentStatus { pending, paid, failed, waived, notRequired, expired }

extension SubscriptionPaymentStatusX on SubscriptionPaymentStatus {
  String get wire => switch (this) {
        SubscriptionPaymentStatus.pending => 'pending',
        SubscriptionPaymentStatus.paid => 'paid',
        SubscriptionPaymentStatus.failed => 'failed',
        SubscriptionPaymentStatus.waived => 'waived',
        SubscriptionPaymentStatus.notRequired => 'not_required',
        SubscriptionPaymentStatus.expired => 'expired',
      };

  String get arabicLabel => switch (this) {
        SubscriptionPaymentStatus.pending => 'بانتظار الدفع',
        SubscriptionPaymentStatus.paid => 'مدفوع',
        SubscriptionPaymentStatus.failed => 'فشل الدفع',
        SubscriptionPaymentStatus.waived => 'مجاني (عرض 2026)',
        SubscriptionPaymentStatus.notRequired => 'بدون رسوم',
        SubscriptionPaymentStatus.expired => 'منتهية',
      };

  static SubscriptionPaymentStatus parse(dynamic v, {SubscriptionPaymentStatus fallback = SubscriptionPaymentStatus.pending}) {
    switch (v?.toString().trim()) {
      case 'paid':
        return SubscriptionPaymentStatus.paid;
      case 'failed':
        return SubscriptionPaymentStatus.failed;
      case 'waived':
        return SubscriptionPaymentStatus.waived;
      case 'not_required':
        return SubscriptionPaymentStatus.notRequired;
      case 'pending':
        return SubscriptionPaymentStatus.pending;
      case 'expired':
        return SubscriptionPaymentStatus.expired;
      default:
        return fallback;
    }
  }
}

/// One delegate inside a (multi-delegate) renewal request.
class RenewalItem extends Equatable {
  final String uid;
  final String fullName;
  final double fee;

  const RenewalItem({required this.uid, required this.fullName, required this.fee});

  Map<String, dynamic> toMap() => {'uid': uid, 'fullName': fullName, 'fee': fee};

  factory RenewalItem.fromMap(Map<String, dynamic> m) => RenewalItem(
        uid: (m['uid'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        fee: (m['fee'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  List<Object?> get props => [uid, fullName, fee];
}

const String kRequestTypeNewDelegate = 'new_delegate';
const String kRequestTypeAddOrganization = 'add_organization';
const String kRequestTypeDeleteDelegate = 'delete_delegate';
const String kRequestTypeRenewal = 'renewal';

class DelegateSubscriptionRequest extends Equatable {
  final String id;
  final String supervisorUid;
  final String supervisorName;
  final String supervisorPhone;
  final String companyUID;
  final String companyName;
  final String organizationUID;
  final String organizationName;
  /// All selected chains (legacy docs may omit this; use [resolvedOrganizationUIDs]).
  final List<String> organizationUIDs;
  final List<String> organizationNames;
  /// Chains the client skipped because the person was already registered there.
  final List<String> skippedDuplicateOrgUIDs;
  final String firstName;
  final String secondName;
  final String thirdName;
  final String fullName;
  final String phoneNumber;
  final String nationalId;
  final String proposedNationalId;
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
  final String requestType;
  final String? existingDelegateUid;
  final String? currentOrganizationName;
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final SubscriptionPaymentStatus paymentStatus;
  final List<String> coveredDelegateUids;
  final List<RenewalItem> items;
  final String? paymobTransactionId;
  final String? paymentError;

  const DelegateSubscriptionRequest({
    required this.id,
    required this.supervisorUid,
    required this.supervisorName,
    required this.supervisorPhone,
    required this.companyUID,
    required this.companyName,
    required this.organizationUID,
    required this.organizationName,
    this.organizationUIDs = const [],
    this.organizationNames = const [],
    this.skippedDuplicateOrgUIDs = const [],
    required this.firstName,
    required this.secondName,
    required this.thirdName,
    required this.fullName,
    required this.phoneNumber,
    required this.nationalId,
    this.proposedNationalId = '',
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
    this.requestType = 'new_delegate',
    this.existingDelegateUid,
    this.currentOrganizationName,
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    this.paymentStatus = SubscriptionPaymentStatus.pending,
    this.coveredDelegateUids = const [],
    this.items = const [],
    this.paymobTransactionId,
    this.paymentError,
  });

  /// Amount this request charges (server re-computes it before Paymob).
  double get amountDue => fee;
  String get periodCode => subscriptionCycle;

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
      if (resolvedOrganizationUIDs.isNotEmpty) 'organizationUIDs': resolvedOrganizationUIDs,
      if (organizationNames.isNotEmpty) 'organizationNames': organizationNames,
      if (skippedDuplicateOrgUIDs.isNotEmpty) 'skippedDuplicateOrgUIDs': skippedDuplicateOrgUIDs,
      'firstName': firstName,
      'secondName': secondName,
      'thirdName': thirdName,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'nationalId': nationalId,
      'proposedNationalId': proposedNationalId,
      'profileImageUrl': profileImageUrl,
      'nationalIdFrontUrl': nationalIdFrontUrl,
      'nationalIdBackUrl': nationalIdBackUrl,
      'paymentMethod': switch (paymentMethod) {
        SubscriptionPaymentMethod.companyDeduction => 'company_deduction',
        SubscriptionPaymentMethod.instaPay => 'instapay',
        SubscriptionPaymentMethod.branchReceipt => 'branch_receipt',
        SubscriptionPaymentMethod.freePromotion => 'free_promotion',
        SubscriptionPaymentMethod.paymob => 'paymob',
        SubscriptionPaymentMethod.notRequired => 'not_required',
      },
      'receiptCode': receiptCode,
      'receiptImageUrl': receiptImageUrl,
      'subscriptionCycle': subscriptionCycle,
      'cycleStartDate': cycleStartDate.toIso8601String(),
      'cycleEndDate': cycleEndDate.toIso8601String(),
      'fee': fee,
      'remainingMonths': remainingMonths,
      'status': status.name,
      'requestType': requestType,
      'existingDelegateUid': existingDelegateUid,
      'currentOrganizationName': currentOrganizationName,
      'rejectionReason': rejectionReason,
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      // Subscription fields read by the server (functions/src/subscription_*.ts).
      'periodCode': subscriptionCycle,
      'amountDue': fee,
      'paymentStatus': paymentStatus.wire,
      if (coveredDelegateUids.isNotEmpty) 'coveredDelegateUids': coveredDelegateUids,
      if (items.isNotEmpty) 'items': items.map((i) => i.toMap()).toList(),
    };
  }

  factory DelegateSubscriptionRequest.fromMap(Map<String, dynamic> map, String docId) {
    SubscriptionPaymentMethod parsePaymentMethod(dynamic val) {
      if (val == 'company_deduction') return SubscriptionPaymentMethod.companyDeduction;
      if (val == 'instapay' || val == 'insta_pay') return SubscriptionPaymentMethod.instaPay;
      if (val == 'free_promotion' || val == 'free') return SubscriptionPaymentMethod.freePromotion;
      if (val == 'paymob') return SubscriptionPaymentMethod.paymob;
      if (val == 'not_required') return SubscriptionPaymentMethod.notRequired;
      return SubscriptionPaymentMethod.branchReceipt;
    }

    SubscriptionRequestStatus parseStatus(dynamic val) {
      if (val == 'approved') return SubscriptionRequestStatus.approved;
      if (val == 'rejected') return SubscriptionRequestStatus.rejected;
      if (val == 'cancelled') return SubscriptionRequestStatus.cancelled;
      if (val == 'expired') return SubscriptionRequestStatus.expired;
      // action_required is still an open request; show it with the pending queue.
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
      organizationUIDs: _stringList(map['organizationUIDs']),
      organizationNames: _stringList(map['organizationNames']),
      skippedDuplicateOrgUIDs: _stringList(map['skippedDuplicateOrgUIDs']),
      firstName: map['firstName'] ?? '',
      secondName: map['secondName'] ?? '',
      thirdName: map['thirdName'] ?? '',
      fullName: map['fullName'] ??
          '${map['firstName'] ?? ''} ${map['secondName'] ?? ''} ${map['thirdName'] ?? ''}'
              .trim(),
      phoneNumber: map['phoneNumber'] ?? '',
      nationalId: map['nationalId'] ?? '',
      proposedNationalId: map['proposedNationalId'] ?? '',
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
      requestType: map['requestType'] as String? ?? 'new_delegate',
      existingDelegateUid: map['existingDelegateUid'] as String?,
      currentOrganizationName: map['currentOrganizationName'] as String?,
      rejectionReason: map['rejectionReason'],
      reviewedBy: map['reviewedBy'],
      reviewedAt: map['reviewedAt'] != null ? parseDate(map['reviewedAt']) : null,
      createdAt: parseDate(map['createdAt']),
      // Legacy requests have no paymentStatus: they were free (2026) or settled manually.
      paymentStatus: SubscriptionPaymentStatusX.parse(map['paymentStatus'],
          fallback: SubscriptionPaymentStatus.waived),
      coveredDelegateUids: (map['coveredDelegateUids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      items: (map['items'] as List?)
              ?.whereType<Map>()
              .map((e) => RenewalItem.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      paymobTransactionId: (map['paymob'] is Map) ? (map['paymob']['transactionId'])?.toString() : null,
      paymentError: map['paymentError'] as String?,
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
    List<String>? organizationUIDs,
    List<String>? organizationNames,
    List<String>? skippedDuplicateOrgUIDs,
    String? firstName,
    String? secondName,
    String? thirdName,
    String? fullName,
    String? phoneNumber,
    String? nationalId,
    String? proposedNationalId,
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
    String? requestType,
    String? existingDelegateUid,
    String? currentOrganizationName,
    String? rejectionReason,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
    SubscriptionPaymentStatus? paymentStatus,
    List<String>? coveredDelegateUids,
    List<RenewalItem>? items,
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
      organizationUIDs: organizationUIDs ?? this.organizationUIDs,
      organizationNames: organizationNames ?? this.organizationNames,
      skippedDuplicateOrgUIDs: skippedDuplicateOrgUIDs ?? this.skippedDuplicateOrgUIDs,
      firstName: firstName ?? this.firstName,
      secondName: secondName ?? this.secondName,
      thirdName: thirdName ?? this.thirdName,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      nationalId: nationalId ?? this.nationalId,
      proposedNationalId: proposedNationalId ?? this.proposedNationalId,
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
      requestType: requestType ?? this.requestType,
      existingDelegateUid: existingDelegateUid ?? this.existingDelegateUid,
      currentOrganizationName: currentOrganizationName ?? this.currentOrganizationName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      coveredDelegateUids: coveredDelegateUids ?? this.coveredDelegateUids,
      items: items ?? this.items,
      paymobTransactionId: paymobTransactionId,
      paymentError: paymentError,
    );
  }

  List<String> get resolvedOrganizationUIDs => resolveOrganizationUIDs(
        organizationUID: organizationUID,
        organizationUIDs: organizationUIDs,
      );

  String nameForOrganization(String uid) {
    final i = organizationUIDs.indexOf(uid);
    if (i >= 0 && i < organizationNames.length && organizationNames[i].trim().isNotEmpty) {
      return organizationNames[i].trim();
    }
    if (uid == organizationUID && organizationName.trim().isNotEmpty) {
      return organizationName.trim();
    }
    return uid;
  }

  bool get isDeleteRequest => requestType == 'delete_delegate';
  bool get isAddOrganizationRequest => requestType == 'add_organization';
  bool get isNewDelegateRequest => requestType == 'new_delegate';
  bool get isRenewalRequest => requestType == kRequestTypeRenewal;
  bool get isNationalIdUpdateRequest => requestType == 'update_national_id';

  /// Staff may activate a new delegate only when the subscription is settled.
  bool get isPaymentSettled =>
      paymentStatus == SubscriptionPaymentStatus.paid ||
      paymentStatus == SubscriptionPaymentStatus.waived ||
      paymentStatus == SubscriptionPaymentStatus.notRequired;

  @override
  List<Object?> get props => [
        id,
        supervisorUid,
        companyUID,
        organizationUID,
        organizationUIDs,
        skippedDuplicateOrgUIDs,
        phoneNumber,
        nationalId,
        proposedNationalId,
        paymentMethod,
        receiptCode,
        subscriptionCycle,
        fee,
        remainingMonths,
        status,
        requestType,
        existingDelegateUid,
        currentOrganizationName,
        createdAt,
        paymentStatus,
        coveredDelegateUids,
        items,
      ];
}
