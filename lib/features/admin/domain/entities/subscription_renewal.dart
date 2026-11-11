import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
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

  const RenewableDelegate({
    required this.uid,
    required this.fullName,
    required this.phoneNumber,
    required this.organizationName,
    this.delegatePublicId,
    this.pendingRenewalRequestId,
  });

  bool get isAwaitingPayment => pendingRenewalRequestId != null;

  @override
  List<Object?> get props => [uid, fullName, phoneNumber, organizationName, delegatePublicId, pendingRenewalRequestId];
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

  /// Selects every delegate that is not already awaiting payment (up to [maxDelegatesPerRenewal]).
  RenewalSelection selectAll(Iterable<RenewableDelegate> delegates) => RenewalSelection(
        delegates
            .where((d) => !d.isAwaitingPayment)
            .map((d) => d.uid)
            .take(SubscriptionCycleHelper.maxDelegatesPerRenewal)
            .toSet(),
      );

  RenewalSelection clear() => const RenewalSelection();

  /// Drops uids no longer in the list (e.g. after a reload).
  RenewalSelection retainOnly(Iterable<RenewableDelegate> delegates) {
    final allowed = delegates.where((d) => !d.isAwaitingPayment).map((d) => d.uid).toSet();
    return RenewalSelection(selectedUids.intersection(allowed));
  }

  double feePerDelegate([DateTime? at]) => SubscriptionCycleHelper.getProratedSubscriptionFee(at);

  /// Sum of each selected delegate's prorated fee (one Paymob payment).
  double total([DateTime? at]) => SubscriptionCycleHelper.totalFor(count, at);

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
