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
