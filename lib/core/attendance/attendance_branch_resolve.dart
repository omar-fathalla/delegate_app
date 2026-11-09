import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';

class ResolvedBranchDocument {
  final String documentId;
  final Map<String, dynamic> data;

  const ResolvedBranchDocument({
    required this.documentId,
    required this.data,
  });
}

/// Reads branch coordinates from Firestore branch documents (nested or legacy top-level).
BranchModel branchModelFromResolvedMap(
  Map<String, dynamic> data, {
  String documentId = '',
}) {
  final withId = <String, dynamic>{
    ...data,
    if (documentId.isNotEmpty) 'id': documentId,
  };
  return BranchModel.fromMap(withId, id: documentId);
}

void registerBranchInLookupMap(
  Map<String, Branch> branchesByName,
  Branch branch,
) {
  final name = branch.branchName.trim();
  if (name.isNotEmpty) {
    branchesByName[name.toLowerCase()] = branch;
  }
  if (branch.id.trim().isNotEmpty) {
    branchesByName[branch.id.toLowerCase()] = branch;
  }
  final org = branch.organizationUID?.trim() ?? '';
  if (org.isNotEmpty && name.isNotEmpty) {
    branchesByName['${org.toLowerCase()}:${name.toLowerCase()}'] = branch;
  }
}

Branch? lookupBranchForAttendanceLog({
  required Map<String, Branch> branchesByName,
  required Map<String, dynamic> log,
  String? fallbackBranchName,
}) {
  final branchId = log['branchId']?.toString().trim();
  if (branchId != null && branchId.isNotEmpty) {
    final byId = branchesByName[branchId.toLowerCase()];
    if (byId != null) return byId;
  }

  final branchName =
      (log['branchName'] ?? fallbackBranchName)?.toString().trim() ?? '';
  final org = (log['branchOrganizationUID'] ?? log['organizationId'])
      ?.toString()
      .trim() ??
      '';
  if (org.isNotEmpty && branchName.isNotEmpty) {
    final scoped =
        branchesByName['${org.toLowerCase()}:${branchName.toLowerCase()}'];
    if (scoped != null) return scoped;
  }
  if (branchName.isNotEmpty) {
    return branchesByName[branchName.toLowerCase()];
  }
  return null;
}
