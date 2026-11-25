import 'package:delegate_app/features/admin/domain/entities/branch.dart';

/// Whether a branch may be used for a check-in in the open chain (TAS-333).
enum BranchChainCheck {
  /// The branch belongs to the open chain.
  ok,

  /// The branch belongs to another chain the delegate is a member of: the
  /// delegate has to switch to that chain first.
  otherOwnChain,

  /// The branch belongs to a chain the delegate is not a member of.
  notMember,
}

/// Checks the chain of the branch about to be recorded on a check-in.
///
/// The check-in is written with `organizationId = currentOrgId`, so the
/// branch must belong to that same chain. A QR code (or a branch document)
/// of any other chain is refused, even at the same location: the scanned
/// branch is never swapped for another one.
BranchChainCheck checkBranchChain({
  required String branchOrganizationUID,
  required String currentOrgId,
  required Iterable<String> memberOrgIds,
}) {
  final org = branchOrganizationUID.trim();
  final current = currentOrgId.trim();
  // Legacy name-only QR codes carry no chain: they resolve in the open chain.
  if (org.isEmpty || org == current) return BranchChainCheck.ok;
  final members = memberOrgIds.map((o) => o.trim()).toSet();
  return members.contains(org)
      ? BranchChainCheck.otherOwnChain
      : BranchChainCheck.notMember;
}

/// Keeps only branches of the delegate's own chains (TAS-333). A branch
/// without a chain id is kept (it was loaded under a chain path).
List<Branch> keepMemberChainBranches(
  Iterable<Branch> branches,
  Set<String> memberOrgIds,
) {
  final members = memberOrgIds.map((o) => o.trim()).toSet();
  return branches.where((b) {
    final org = (b.organizationUID ?? '').trim();
    return org.isEmpty || members.contains(org);
  }).toList();
}
