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
  });

  final Set<String> duplicateOrgUids;
  final String? existingDelegateUid;
  final String? existingDelegateOrganizationUID;
}

class DuplicateChainLookupException implements Exception {
  const DuplicateChainLookupException([this.message = 'تعذر التحقق من المندوبين المسجلين. أعد المحاولة.']);
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

  for (final orgId in orgs) {
    final col = firestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(companyUID)
        .collection('delegates');

    Future<QuerySnapshot<Map<String, dynamic>>> query(String field, String value) async {
      try {
        return await col.where(field, isEqualTo: value).limit(2).get();
      } catch (e) {
        throw DuplicateChainLookupException(
          'تعذر التحقق من المندوبين المسجلين. أعد المحاولة.',
        );
      }
    }

    Future<void> collect(String field, String value) async {
      if (value.isEmpty) return;
      final snap = await query(field, value);
      if (snap.docs.isEmpty) return;
      found.add(orgId);
      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = (data['uid'] ?? doc.id).toString();
        recordUid(orgId, uid);
      }
    }

    await collect('nationalId', nid);
    await collect('nationalityID', nid);
    await collect('phoneNumber', phone);
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
      found.addAll(ids.intersection(orgs));
      final existing = (data['existingDelegateUid'] ?? '').toString().trim();
      if (existing.isNotEmpty) recordUid(primary.isNotEmpty ? primary : existing, existing);
    }
  }

  await scanRequests('nationalId', nid);
  await scanRequests('phoneNumber', phone);
  return DuplicateChainLookup(
    duplicateOrgUids: found,
    existingDelegateUid: existingUid,
    existingDelegateOrganizationUID: existingOrg,
  );
}
