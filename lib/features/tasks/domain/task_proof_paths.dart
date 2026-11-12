/// Maximum number of proof photos a single uploader may attach (Phase 4).
const int kMaxTaskProofImages = 3;

const String kTaskProofPurpose = 'task_proof_image';
const String kTaskProofRoot = 'task_proof';

/// Exact N1-r filename: proof_{uid}_{token}.jpg
String taskProofFileName({
  required String uploaderUid,
  required String token,
}) => 'proof_${uploaderUid}_$token.jpg';

String taskProofPath({
  required String companyId,
  required String uploaderUid,
  required String token,
}) =>
    '$kTaskProofRoot/$companyId/$uploaderUid/${taskProofFileName(uploaderUid: uploaderUid, token: token)}';

/// Normalize and cap a per-uploader proof path list at [kMaxTaskProofImages].
List<String> resolveTaskProofPaths(Iterable<String>? imagePaths) {
  final out = <String>[];
  final seen = <String>{};
  if (imagePaths != null) {
    for (final raw in imagePaths) {
      final path = raw.trim().replaceAll('\\', '/');
      if (path.isEmpty || seen.contains(path)) continue;
      if (!path.startsWith('$kTaskProofRoot/')) continue;
      seen.add(path);
      out.add(path);
      if (out.length >= kMaxTaskProofImages) break;
    }
  }
  return List<String>.unmodifiable(out);
}

String normalizeRoleKey(String? role) =>
    (role ?? '').trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

const _companySupervisorRoles = {
  'company_admin',
  'companyadmin',
  'admin',
  'supervisor',
  'company_supervisor',
};

const _proofUploaderRoles = {
  'delegate',
  'promoter',
  'field_delegate',
  'marketing',
  'marketingpromotion',
  'marketing_promotion',
  'branches_marketing',
  'branches_marketing_manager',
  'branchesmarketingmanager',
};

/// Same-company company supervisors/admins may read every uploader's proofs.
bool isCompanySupervisorRole(String? role) =>
    _companySupervisorRoles.contains(normalizeRoleKey(role));

/// Field delegates and sector recipients who can complete a task.
bool isTaskProofUploaderRole(String? role) =>
    _proofUploaderRoles.contains(normalizeRoleKey(role));

const _branchMarketingRoles = {
  'marketing',
  'branches_marketing',
  'branchesmarketing',
  'branches_marketing_manager',
  'branchesmarketingmanager',
};

const _marketingPromotionRoles = {'marketing_promotion', 'marketingpromotion'};

/// B1: whether the signed-in user may attach proof photos to a task.
/// Only the task's assignee or its intended recipients, in the task's
/// company, and never on a cancelled task. «الكل» is field delegates only;
/// sector tasks accept the matching sector role. Mirrors the server rules.
bool canWriteTaskProof({
  required String? role,
  required Iterable<String?> viewerIds,
  required String? viewerCompanyId,
  required String taskCompanyId,
  required String assignedTo,
  required bool cancelled,
}) {
  if (cancelled) return false;
  final key = normalizeRoleKey(role);
  if (!_proofUploaderRoles.contains(key)) return false;
  final taskCo = taskCompanyId.trim();
  if (taskCo.isEmpty) return false;
  final viewerCo = (viewerCompanyId ?? '').trim();
  final sameCompany = viewerCo == taskCo;
  final assigned = assignedTo.trim();
  if (assigned.isEmpty) return false;
  if (assigned == 'all' || assigned == 'الكل') {
    return sameCompany && key == 'delegate';
  }
  if (assigned == 'all_branch_marketing') {
    return _branchMarketingRoles.contains(key) &&
        (sameCompany || viewerCo.isEmpty);
  }
  if (assigned == 'all_marketing_promotion') {
    return _marketingPromotionRoles.contains(key) &&
        (sameCompany || viewerCo.isEmpty);
  }
  final ids = {
    for (final id in viewerIds)
      if (id != null && id.trim().isNotEmpty) id.trim(),
  };
  return sameCompany && ids.contains(assigned);
}
