import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:equatable/equatable.dart';

/// Status reason the server writes when a period ends without a paid subscription.
const String kSubscriptionExpiredReason = 'subscription_expired';

/// A suspended (expired) app-added delegate the supervisor can renew.
class RenewableDelegate extends Equatable {
  final String uid;
  final String fullName;
  final String phoneNumber;
  final String organizationName;
  final String? delegatePublicId;

  /// Set when the delegate is already in an unpaid renewal (awaiting Paymob).
  final String? pendingRenewalRequestId;

  /// Period this row is for (current or next). Empty in older callers.
  final String periodCode;

  /// Live delegate status / reason (for filters and excluded-row copy).
  final String status;
  final String statusReason;

  /// Already paid or waived for [periodCode]; not selectable.
  final bool isCovered;
  final String? exclusionReason;

  const RenewableDelegate({
    required this.uid,
    required this.fullName,
    required this.phoneNumber,
    required this.organizationName,
    this.delegatePublicId,
    this.pendingRenewalRequestId,
    this.periodCode = '',
    this.status = '',
    this.statusReason = '',
    this.isCovered = false,
    this.exclusionReason,
  });

  bool get isAwaitingPayment => pendingRenewalRequestId != null;

  bool get isSelectable => !isAwaitingPayment && !isCovered;

  bool get isSuspendedExpired =>
      status == 'suspended' && statusReason == kSubscriptionExpiredReason;

  /// Unique across both period lists (same uid may appear twice).
  String get selectionKey => periodCode.isEmpty ? uid : '$uid|$periodCode';

  @override
  List<Object?> get props => [
    uid,
    fullName,
    phoneNumber,
    organizationName,
    delegatePublicId,
    pendingRenewalRequestId,
    periodCode,
    status,
    statusReason,
    isCovered,
    exclusionReason,
  ];
}

/// UI-agnostic renewal selection: works for the multi-select page today and a
/// per-row "renew" button later (a selection of one).
class RenewalSelection extends Equatable {
  final Set<String> selectedUids;

  const RenewalSelection([this.selectedUids = const {}]);

  factory RenewalSelection.single(String uid) => RenewalSelection({uid});

  bool isSelected(String uid) => selectedUids.contains(uid);
  int get count => selectedUids.length;
  bool get isEmpty => selectedUids.isEmpty;

  RenewalSelection toggle(String uid) {
    final next = Set<String>.from(selectedUids);
    if (next.contains(uid)) {
      next.remove(uid);
    } else if (next.length < SubscriptionCycleHelper.maxDelegatesPerRenewal) {
      next.add(uid);
    }
    return RenewalSelection(next);
  }

  /// Selects every selectable delegate (up to [maxDelegatesPerRenewal]).
  RenewalSelection selectAll(Iterable<RenewableDelegate> delegates) =>
      RenewalSelection(
        delegates
            .where((d) => d.isSelectable)
            .map((d) => d.selectionKey)
            .take(SubscriptionCycleHelper.maxDelegatesPerRenewal)
            .toSet(),
      );

  RenewalSelection clear() => const RenewalSelection();

  /// Drops uids no longer in the list (e.g. after a reload).
  RenewalSelection retainOnly(Iterable<RenewableDelegate> delegates) {
    final allowed = delegates
        .where((d) => d.isSelectable)
        .map((d) => d.selectionKey)
        .toSet();
    return RenewalSelection(selectedUids.intersection(allowed));
  }

  double feePerDelegate([
    DateTime? at,
    String? companyUID,
    String? periodCode,
  ]) {
    if (periodCode != null && periodCode.isNotEmpty) {
      return SubscriptionCycleHelper.getFeeForPeriod(
        periodCode,
        at,
        companyUID,
      );
    }
    return SubscriptionCycleHelper.getProratedSubscriptionFee(at, companyUID);
  }

  /// Sum of each selected delegate's fee (one Paymob payment).
  double total([DateTime? at, String? companyUID, String? periodCode]) {
    if (periodCode != null && periodCode.isNotEmpty) {
      return SubscriptionCycleHelper.roundMoney(
        feePerDelegate(at, companyUID, periodCode) * count,
      );
    }
    return SubscriptionCycleHelper.totalFor(count, at, companyUID);
  }

  @override
  List<Object?> get props => [selectedUids.toList()..sort()];
}

/// Who may open «تجديد المناديب» and create a renewal (Mohamed, Phase 1 item 2).
/// Supervisors share [UserRole.admin] with company admins. HR and org-admins
/// are also allowed, but only inside their company — an empty [companyUID]
/// is fail-closed (the item stays hidden). Paymob online only, cap 100.
bool canCreateSubscriptionRenewal({
  required UserRole role,
  required String companyUID,
}) {
  if (companyUID.trim().isEmpty) return false;
  switch (role) {
    case UserRole.admin: // company admin and company supervisor
    case UserRole.hr:
    case UserRole.organizationAdmin:
      return true;
    default:
      return false;
  }
}

/// One paid (or pending) renewal request, for the in-app receipt.
class RenewalReceipt extends Equatable {
  final String requestId;
  final String periodCode;
  final double amount;
  final int remainingMonths;
  final List<RenewalItem> items;
  final SubscriptionPaymentStatus paymentStatus;
  final String? transactionId;
  final String? paidAt;
  final String companyName;
  final String organizationName;

  const RenewalReceipt({
    required this.requestId,
    required this.periodCode,
    required this.amount,
    required this.remainingMonths,
    required this.items,
    required this.paymentStatus,
    this.transactionId,
    this.paidAt,
    this.companyName = '',
    this.organizationName = '',
  });

  int get delegateCount => items.length;

  @override
  List<Object?> get props => [
    requestId,
    periodCode,
    amount,
    remainingMonths,
    items,
    paymentStatus,
    transactionId,
    paidAt,
    companyName,
    organizationName,
  ];
}

enum RenewalListFilter { all, suspended, expiringSoon }

/// "قرب ينتهي الاشتراك": last [months] months of the current period (inclusive).
bool isRenewalExpiringSoon(DateTime now, {int months = 2}) =>
    SubscriptionCycleHelper.getRemainingMonthsInCycle(now) <= months;
