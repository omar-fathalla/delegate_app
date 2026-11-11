import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-chain duplicate check under one company (national ID or phone).
/// A chain is a duplicate if a delegate doc already exists there, or a
/// pending `delegate_requests` doc already lists that organization.
Future<Set<String>> findDuplicateChainUids({
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
  if (orgs.isEmpty || companyUID.trim().isEmpty) return {};
  final nid = nationalId.trim();
  final phone = phoneNumber.trim();
  if (nid.isEmpty && phone.isEmpty) return {};

  final found = <String>{};

  for (final orgId in orgs) {
    final col = firestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(companyUID)
        .collection('delegates');
    Future<bool> exists(String field, String value) async {
      if (value.isEmpty) return false;
      try {
        final snap = await col.where(field, isEqualTo: value).limit(1).get();
        return snap.docs.isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    if (await exists('nationalId', nid) ||
        await exists('nationalityID', nid) ||
        await exists('phoneNumber', phone)) {
      found.add(orgId);
    }
  }

  Future<void> scanRequests(String field, String value) async {
    if (value.isEmpty) return;
    try {
      final snap = await firestore
          .collection('delegate_requests')
          .where('companyUID', isEqualTo: companyUID)
          .where(field, isEqualTo: value)
          .where('status', isEqualTo: 'pending')
          .limit(20)
          .get();
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
      }
    } catch (_) {}
  }

  await scanRequests('nationalId', nid);
  await scanRequests('phoneNumber', phone);
  return found;
}
