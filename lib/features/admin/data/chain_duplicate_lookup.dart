import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-chain duplicate check under one company (national ID or phone).
/// A chain is a duplicate if a delegate doc already exists there, or a
/// pending `delegate_requests` doc already lists that organization.
///
/// Fails closed: a query error is thrown so the caller can abort rather
/// than treat the chain as free. When a live delegate is found,
/// [existingDelegateUid] is set so remaining chains can be attached to
/// that identity.
class DuplicateChainLookup {
  const DuplicateChainLookup({
    required this.duplicateOrgUids,
    this.existingDelegateUid,
    this.existingDelegateOrganizationUID,
    this.delegateOrgUids = const {},
    this.pendingOrgUids = const {},
  });

  final Set<String> duplicateOrgUids;

  /// Subset of [duplicateOrgUids] where a delegate doc already exists.
  final Set<String> delegateOrgUids;

  /// Subset of [duplicateOrgUids] listed on a pending `delegate_requests` doc.
  final Set<String> pendingOrgUids;
  final String? existingDelegateUid;
  final String? existingDelegateOrganizationUID;
}

class DuplicateChainLookupException implements Exception {
  const DuplicateChainLookupException([
    this.message = 'تعذر التحقق من المندوبين المسجلين. أعد المحاولة.',
  ]);
  final String message;
  @override
  String toString() => message;
}

Future<Set<String>> findDuplicateChainUids({
  required FirebaseFirestore firestore,
  required String companyUID,
  required String nationalId,
  required String phoneNumber,
  required Iterable<String> organizationUIDs,
}) async {
  final result = await lookupDuplicateChains(
    firestore: firestore,
    companyUID: companyUID,
    nationalId: nationalId,
    phoneNumber: phoneNumber,
    organizationUIDs: organizationUIDs,
  );
  return result.duplicateOrgUids;
}

Future<DuplicateChainLookup> lookupDuplicateChains({
  required FirebaseFirestore firestore,
  required String companyUID,
  required String nationalId,
  required String phoneNumber,
  required Iterable<String> organizationUIDs,
}) async {
  final orgs = {
    for (final id in organizationUIDs)
      if (id.trim().isNotEmpty) id.trim(),
  };
  if (orgs.isEmpty || companyUID.trim().isEmpty) {
    return const DuplicateChainLookup(duplicateOrgUids: {});
  }
  final nid = nationalId.trim();
  final phone = phoneNumber.trim();
  if (nid.isEmpty && phone.isEmpty) {
    return const DuplicateChainLookup(duplicateOrgUids: {});
  }

  final found = <String>{};
  final onDelegateDocs = <String>{};
  final onPendingRequests = <String>{};
  String? existingUid;
  String? existingOrg;
  final seenUids = <String>{};

  void recordUid(String orgId, String uid) {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    seenUids.add(clean);
    existingUid ??= clean;
    existingOrg ??= orgId;
    if (seenUids.length > 1) {
      throw const DuplicateChainLookupException(
        'تم العثور على أكثر من هوية لنفس المندوب في هذه الشركة. تواصل مع الدعم الفني.',
      );
    }
  }

  String _nationalIdOf(Map<String, dynamic> data) {
    final raw = (data['nationalId'] ?? data['nationalityID'] ?? '').toString();
    return raw.trim();
  }

  /// Phone match with a different national ID is a conflict: never attach
  /// the typed person to that existing record.
  void _assertPhoneMatchesIdentity(Map<String, dynamic> data) {
    if (nid.isEmpty) return;
    final existingNid = _nationalIdOf(data);
    if (existingNid.isEmpty) {
      throw const DuplicateChainLookupException(
        'رقم الهاتف مسجّل لمندوب دون رقم قومي مؤكد. لا يمكن ربط هذا الطلب بتلك الهوية. راجع الرقم القومي ورقم الهاتف.',
      );
    }
    if (existingNid != nid) {
      throw const DuplicateChainLookupException(
        'رقم الهاتف مسجّل لمندوب برقم قومي مختلف. لا يمكن ربط هذا الطلب بتلك الهوية. راجع الرقم القومي ورقم الهاتف.',
      );
    }
  }

  for (final orgId in orgs) {
    final col = firestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(companyUID)
        .collection('delegates');

    Future<QuerySnapshot<Map<String, dynamic>>> query(
      String field,
      String value,
    ) async {
      try {
        return await col.where(field, isEqualTo: value).limit(2).get();
      } catch (e) {
        throw DuplicateChainLookupException(
          'تعذر التحقق من المندوبين المسجلين. أعد المحاولة.',
        );
      }
    }

    Future<void> collect(
      String field,
      String value, {
      required bool phoneMatch,
    }) async {
      if (value.isEmpty) return;
      final snap = await query(field, value);
      if (snap.docs.isEmpty) return;
      found.add(orgId);
      onDelegateDocs.add(orgId);
      for (final doc in snap.docs) {
        final data = doc.data();
        if (phoneMatch) _assertPhoneMatchesIdentity(data);
        final uid = (data['uid'] ?? doc.id).toString();
        recordUid(orgId, uid);
      }
    }

    await collect('nationalId', nid, phoneMatch: false);
    await collect('nationalityID', nid, phoneMatch: false);
    await collect('phoneNumber', phone, phoneMatch: true);
  }

  Future<void> scanRequests(String field, String value) async {
    if (value.isEmpty) return;
    late final QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await firestore
          .collection('delegate_requests')
          .where('companyUID', isEqualTo: companyUID)
          .where(field, isEqualTo: value)
          .where('status', isEqualTo: 'pending')
          .limit(20)
          .get();
    } catch (_) {
      throw const DuplicateChainLookupException(
        'تعذر التحقق من المندوبين المسجلين. أعد المحاولة.',
      );
    }
    for (final doc in snap.docs) {
      final data = doc.data();
      final primary = (data['organizationUID'] ?? '').toString().trim();
      final list = data['organizationUIDs'];
      final ids = <String>{
        if (primary.isNotEmpty) primary,
        if (list is List)
          for (final e in list)
            if (e.toString().trim().isNotEmpty) e.toString().trim(),
      };
      final hits = ids.intersection(orgs);
      found.addAll(hits);
      onPendingRequests.addAll(hits);
      // Pending requests only occupy the chain; identity checks that would
      // attach to a live record run against delegate docs, not this scan.
      final existing = (data['existingDelegateUid'] ?? '').toString().trim();
      if (existing.isNotEmpty)
        recordUid(primary.isNotEmpty ? primary : existing, existing);
    }
  }

  await scanRequests('nationalId', nid);
  await scanRequests('phoneNumber', phone);
  return DuplicateChainLookup(
    duplicateOrgUids: found,
    existingDelegateUid: existingUid,
    existingDelegateOrganizationUID: existingOrg,
    delegateOrgUids: onDelegateDocs,
    pendingOrgUids: onPendingRequests,
  );
}

/// Chain states for linking a KNOWN existing delegate to more chains (the
/// «ربط بسلاسل إضافية» / HR web «إضافة سلاسل» flow).
///
/// Unlike [lookupDuplicateChains] (a new person typed into the add form),
/// the identity is already known, so a chain counts as linked when the
/// delegate's own doc exists there (a path read, no index needed) or another
/// doc there carries the same national ID. It does NOT query nested
/// `delegates` by phoneNumber: on prod that field has no collection-scope
/// index, so the query fails with FAILED_PRECONDITION.
/// Pending requests use the same `delegate_requests` scan as the add form.
/// Throws [DuplicateChainLookupException] on a query error.
Future<DuplicateChainLookup> lookupLinkChainStates({
  required FirebaseFirestore firestore,
  required String companyUID,
  required String delegateUid,
  required String nationalId,
  required String phoneNumber,
  required Iterable<String> organizationUIDs,
}) async {
  final orgs = {
    for (final id in organizationUIDs)
      if (id.trim().isNotEmpty) id.trim(),
  };
  final co = companyUID.trim();
  if (orgs.isEmpty || co.isEmpty) {
    return const DuplicateChainLookup(duplicateOrgUids: {});
  }
  final uid = delegateUid.trim();
  final nid = nationalId.trim();
  final phone = phoneNumber.trim();
  final linked = <String>{};
  final pending = <String>{};
  const failure = DuplicateChainLookupException();

  for (final orgId in orgs) {
    final col = firestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(co)
        .collection('delegates');
    try {
      if (uid.isNotEmpty && (await col.doc(uid).get()).exists) {
        linked.add(orgId);
        continue;
      }
      if (nid.isEmpty) continue;
      for (final field in const ['nationalId', 'nationalityID']) {
        final snap = await col.where(field, isEqualTo: nid).limit(1).get();
        if (snap.docs.isNotEmpty) {
          linked.add(orgId);
          break;
        }
      }
    } catch (_) {
      throw failure;
    }
  }

  Future<void> scanRequests(String field, String value) async {
    if (value.isEmpty) return;
    late final QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await firestore
          .collection('delegate_requests')
          .where('companyUID', isEqualTo: co)
          .where(field, isEqualTo: value)
          .where('status', isEqualTo: 'pending')
          .limit(20)
          .get();
    } catch (_) {
      throw failure;
    }
    for (final doc in snap.docs) {
      final data = doc.data();
      final primary = (data['organizationUID'] ?? '').toString().trim();
      final list = data['organizationUIDs'];
      final ids = <String>{
        if (primary.isNotEmpty) primary,
        if (list is List)
          for (final e in list)
            if (e.toString().trim().isNotEmpty) e.toString().trim(),
      };
      pending.addAll(ids.intersection(orgs));
    }
  }

  await scanRequests('nationalId', nid);
  await scanRequests('phoneNumber', phone);
  return DuplicateChainLookup(
    duplicateOrgUids: {...linked, ...pending},
    existingDelegateUid: uid.isEmpty ? null : uid,
    delegateOrgUids: linked,
    pendingOrgUids: pending.difference(linked),
  );
}
