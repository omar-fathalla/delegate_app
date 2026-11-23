import 'package:cloud_firestore/cloud_firestore.dart';

/// Chains hidden from every picker (Fathalla has its own website signup).
bool isHiddenChain({required String uid, required String name}) {
  final n = name.trim().toLowerCase();
  final u = uid.trim().toLowerCase();
  return n.contains('fathalla') ||
      n.contains('فتح الله') ||
      n.contains('فتح_الله') ||
      u.contains('fathalla') ||
      u.contains('فتح_الله');
}

/// Fields that belong to one chain's record and are never copied from the
/// company's record in another chain.
const Set<String> kChainSpecificCompanyFields = {
  'id',
  'uid',
  'organizationUID',
  'organizationName',
  'organizationCode',
  'companyCodeInOrg',
  'status',
  'delegates',
  'delegatesCount',
  'totalApprovedDelegates',
  'admins',
  'deferredPayment',
  'createdAt',
  'updatedAt',
  'registeredVia',
  'registeredFromRequestId',
  'registeredFromOrganizationUID',
  'companyCodeInOrgPending',
};

/// The record written under organizations/{orgId}/companies/{companyUID}
/// when an approved request puts the company in a chain it was not in.
///
/// Company-wide fields (name, type, commercial register, tax card, document
/// URLs, the deferred-payment flag, phone…) come from [template], the
/// company's record in another chain. Chain fields are set for the new
/// chain; counters and the deferred amount start at 0.
Map<String, dynamic> buildChainCompanyRecord({
  required Map<String, dynamic>? template,
  required String companyUID,
  required String companyName,
  required String orgId,
  required String orgName,
  required String orgCode,
  required String? companyCode,
  required String status,
  String? templateOrgId,
  String? requestId,
}) {
  final data = <String, dynamic>{
    if (template != null)
      for (final e in template.entries)
        if (!kChainSpecificCompanyFields.contains(e.key)) e.key: e.value,
  };
  final name = (template?['name'] ?? '').toString().trim();
  data['id'] = companyUID;
  data['uid'] = companyUID;
  data['name'] = name.isNotEmpty ? name : companyName;
  data['organizationUID'] = orgId;
  data['organizationName'] = orgName;
  data['organizationCode'] = orgCode;
  data['companyCodeInOrg'] = companyCode ?? '';
  if (companyCode == null || companyCode.isEmpty) {
    data['companyCodeInOrgPending'] = true;
  }
  data['status'] = status;
  data['delegates'] = 0;
  data['delegatesCount'] = 0;
  data['totalApprovedDelegates'] = 0;
  data['deferredPayment'] = 0;
  data['hasDeferredPayment'] = template?['hasDeferredPayment'] == true;
  final admins = template?['admins'];
  data['admins'] = admins is num ? 0 : (admins ?? 0);
  data['registeredVia'] = 'add_organization_approval';
  if (requestId != null && requestId.isNotEmpty) {
    data['registeredFromRequestId'] = requestId;
  }
  if (templateOrgId != null && templateOrgId.isNotEmpty) {
    data['registeredFromOrganizationUID'] = templateOrgId;
  }
  data['createdAt'] = FieldValue.serverTimestamp();
  data['updatedAt'] = FieldValue.serverTimestamp();
  return data;
}

/// Status written on a new chain record: the template's value when it is an
/// approved/active one (keeps that project's convention), else 'active'.
String chainRecordStatus(Map<String, dynamic>? template) {
  final s = (template?['status'] ?? '').toString().trim();
  const approved = {'active', 'Active', 'approved', 'Approved', 'ACTIVE', 'APPROVED'};
  return approved.contains(s) ? s : 'active';
}

/// Makes sure the company has a record in every chain in [chains]
/// (orgId -> chain name) and that the supervisor is an admin there, like
/// mobile 1.14.3 approvals did. Idempotent: existing records are never
/// overwritten. Returns the chains where a record was created.
Future<List<String>> ensureCompanyInChains({
  required FirebaseFirestore firestore,
  required String companyUID,
  required String companyName,
  required Map<String, String> chains,
  required String supervisorUid,
  required String supervisorName,
  required String supervisorPhone,
  Iterable<String> preferredTemplateOrgs = const [],
  String? requestId,
}) async {
  final co = companyUID.trim();
  if (co.isEmpty || chains.isEmpty) return const [];
  final created = <String>[];

  // Lazily find the company's record in another chain.
  Map<String, dynamic>? template;
  String? templateOrgId;
  var templateSearched = false;
  Future<void> findTemplate() async {
    if (templateSearched) return;
    templateSearched = true;
    final tried = <String>{};
    Future<bool> tryOrg(String orgId) async {
      if (orgId.isEmpty || !tried.add(orgId)) {
        return false;
      }
      final snap = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(co)
          .get();
      if (!snap.exists) return false;
      template = snap.data();
      templateOrgId = orgId;
      return true;
    }

    for (final id in preferredTemplateOrgs) {
      if (await tryOrg(id.trim())) return;
    }
    final orgs = await firestore.collection('organizations').get();
    for (final o in orgs.docs) {
      if (await tryOrg(o.id)) return;
    }
  }

  for (final entry in chains.entries) {
    final orgId = entry.key.trim();
    if (orgId.isEmpty) continue;
    final orgRef = firestore.collection('organizations').doc(orgId);
    final ref = orgRef.collection('companies').doc(co);
    final existing = await ref.get();
    if (!existing.exists) {
      await findTemplate();
      final orgSnap = await orgRef.get();
      final org = orgSnap.data() ?? const <String, dynamic>{};
      final orgName = entry.value.trim().isNotEmpty
          ? entry.value.trim()
          : (org['name'] ?? org['title'] ?? orgId).toString();
      final orgCode = (org['code'] ?? org['organizationCode'] ?? '').toString();
      final companyCode = await _freeCompanyCode(
        firestore,
        orgId,
        co,
        (template?['companyCodeInOrg'] ?? '').toString().trim(),
      );
      final record = buildChainCompanyRecord(
        template: template,
        companyUID: co,
        companyName: companyName,
        orgId: orgId,
        orgName: orgName,
        orgCode: orgCode,
        companyCode: companyCode,
        status: chainRecordStatus(template),
        templateOrgId: templateOrgId,
        requestId: requestId,
      );
      final wrote = await firestore.runTransaction<bool>((tx) async {
        final again = await tx.get(ref);
        if (again.exists) return false;
        tx.set(ref, record);
        return true;
      });
      if (wrote) created.add(orgId);
    }

    final sup = supervisorUid.trim();
    if (sup.isEmpty) continue;
    final adminRef = ref.collection('admins').doc(sup);
    final adminSnap = await adminRef.get();
    if (!adminSnap.exists) {
      await adminRef.set({
        'uid': sup,
        'name': supervisorName,
        'phone': supervisorPhone,
        'role': 'company-admin',
        'companyUID': co,
        'companyName': companyName,
        'organizationUID': orgId,
        'organizationName': entry.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
  return created;
}

/// The company's code from its other chain, if no other company in [orgId]
/// already uses it. Null when it is taken or cannot be checked (the record
/// is then flagged companyCodeInOrgPending for the chain to assign one).
Future<String?> _freeCompanyCode(
  FirebaseFirestore firestore,
  String orgId,
  String companyUID,
  String code,
) async {
  if (code.isEmpty) return null;
  try {
    final snap = await firestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .where('companyCodeInOrg', isEqualTo: code)
        .limit(2)
        .get();
    final taken = snap.docs.any((d) => d.id != companyUID);
    return taken ? null : code;
  } catch (_) {
    return null;
  }
}

/// Ids in `config/subscriptions.freeChainOrgUids` (the base chain). Empty when
/// the config is missing or unreadable.
Future<Set<String>> loadFreeChainIds(FirebaseFirestore firestore) async {
  try {
    final cfg = await firestore.doc('config/subscriptions').get();
    final raw = cfg.data()?['freeChainOrgUids'];
    if (raw is! List) return const {};
    return {
      for (final v in raw)
        if ((v?.toString().trim() ?? '').isNotEmpty) v.toString().trim(),
    };
  } catch (_) {
    return const {};
  }
}

/// Client re-check used when the server stamp is missing (or is the old
/// "org_not_in_company" failure): every chain must exist, and a hidden chain
/// is allowed only when the company is already in it, or when it is the base
/// chain (TAS-254 / TAS-256: every new delegate is registered there and
/// approval registers the company in it). Returns the first bad chain id, or
/// null.
Future<String?> firstInvalidRequestChain({
  required FirebaseFirestore firestore,
  required String companyUID,
  required List<String> orgIds,
}) async {
  // Every chain in parallel; the first bad one in request order wins.
  final ids = [
    for (final raw in orgIds)
      if (raw.trim().isNotEmpty) raw.trim(),
  ];
  final freeChains = await loadFreeChainIds(firestore);
  final bad = await Future.wait(ids.map((orgId) async {
    final org = await firestore.collection('organizations').doc(orgId).get();
    if (!org.exists) return true;
    if (freeChains.contains(orgId)) return false;
    final data = org.data() ?? const <String, dynamic>{};
    final name = (data['name'] ?? data['title'] ?? orgId).toString();
    if (isHiddenChain(uid: orgId, name: name)) {
      final co = await org.reference.collection('companies').doc(companyUID.trim()).get();
      if (!co.exists) return true;
    }
    return false;
  }));
  for (var i = 0; i < ids.length; i++) {
    if (bad[i]) return ids[i];
  }
  return null;
}

const String kRequestChainUnavailableMessage =
    'لا يمكن الطلب على سلسلة غير متاحة. حدّث الصفحة واختر سلسلة أخرى.';
const String kRegisterCompanyInChainDeniedMessage =
    'تعذر تسجيل الشركة في السلسلة الجديدة: ليس لديك صلاحية على كل السلاسل المطلوبة.';

/// True when the server stamp on a request blocks approval. Only a real
/// 'failed' (chain missing / hidden) blocks; a missing stamp or the old
/// 'org_not_in_company' reason falls back to [firstInvalidRequestChain].
bool approvalStampBlocks(Map<String, dynamic>? request) {
  final mark = (request?['orgCompanyCheck'] ?? '').toString();
  if (mark != 'failed') return false;
  final reason = (request?['orgCompanyCheckReason'] ?? '').toString();
  return reason != 'org_not_in_company';
}
