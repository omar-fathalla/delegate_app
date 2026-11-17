import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/company_chain_registration.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Company-level «طلب ضم سلسلة» (Mohamed, 17 Nov 2026).
///
/// A company asks to join one or more chains. There is no delegate on the
/// request. Approval registers the company in the chain (same
/// [ensureCompanyInChains] as before). After that every active delegate of
/// the company is linked to every company chain automatically by the
/// `autoLinkOnCompanyJoin` / `autoLinkOnDelegateActive` Cloud Functions,
/// which write the same per-chain delegate docs app 1.14.3 already reads.
///
/// Storage: one doc per (company, chain) in [kCompanyChainRequestsCollection],
/// so a chain admin can approve only their own chain. Docs sent together
/// share a `batchId`.
const String kCompanyChainRequestsCollection = 'company_chain_requests';

/// Upper bound per send. Not a business cap (there is no chain cap): it
/// keeps one send inside a single 500-write batch with lots of room.
const int kCompanyChainRequestBatchLimit = 100;

/// A chain in the company picker.
class CompanyChainOption {
  const CompanyChainOption({
    required this.uid,
    required this.name,
    required this.joined,
  });

  final String uid;
  final String name;

  /// The company already has organizations/{uid}/companies/{companyUID}.
  final bool joined;
}

class _CatalogEntry {
  _CatalogEntry(this.future) : at = DateTime.now();
  final Future<List<CompanyChainOption>> future;
  final DateTime at;
}

/// Per-session cache of the chain catalog per company. The HR page
/// prefetches it when it opens, so the picker shows at once.
class CompanyChainCatalog {
  CompanyChainCatalog._();

  static const Duration ttl = Duration(minutes: 5);
  static final Map<String, _CatalogEntry> _cache = {};

  static void clear([String? companyUID]) {
    if (companyUID == null) {
      _cache.clear();
    } else {
      _cache.remove(companyUID.trim());
    }
  }

  /// Every visible chain (the hidden Fathalla chain is left out unless the
  /// company is already in it), sorted by name, with [CompanyChainOption.joined].
  /// Two round trips in total: the organizations list, then all
  /// organizations/{org}/companies/{companyUID} reads in parallel.
  static Future<List<CompanyChainOption>> fetch({
    required FirebaseFirestore firestore,
    required String companyUID,
    bool forceRefresh = false,
  }) {
    final co = companyUID.trim();
    final hit = _cache[co];
    if (!forceRefresh && hit != null && DateTime.now().difference(hit.at) < ttl) {
      return hit.future;
    }
    final future = _load(firestore, co);
    _cache[co] = _CatalogEntry(future);
    // A failed load must not stay cached.
    future.catchError((Object _) {
      if (identical(_cache[co]?.future, future)) _cache.remove(co);
      return const <CompanyChainOption>[];
    });
    return future;
  }

  static Future<List<CompanyChainOption>> _load(
    FirebaseFirestore firestore,
    String co,
  ) async {
    final snap = await firestore.collection('organizations').get();
    final docs = snap.docs;
    final joined = co.isEmpty
        ? List<bool>.filled(docs.length, false)
        : await Future.wait(docs.map((d) async {
            try {
              return (await d.reference.collection('companies').doc(co).get()).exists;
            } catch (_) {
              return false;
            }
          }));
    final out = <CompanyChainOption>[];
    for (var i = 0; i < docs.length; i++) {
      final data = docs[i].data();
      final name = (data['name'] ?? data['title'] ?? docs[i].id).toString().trim();
      if (isHiddenChain(uid: docs[i].id, name: name) && !joined[i]) continue;
      out.add(CompanyChainOption(uid: docs[i].id, name: name, joined: joined[i]));
    }
    out.sort(compareChainNames);
    return out;
  }
}

/// Alphabetical, case-insensitive, stable on uid.
int compareChainNames(CompanyChainOption a, CompanyChainOption b) {
  final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return c != 0 ? c : a.uid.compareTo(b.uid);
}

/// Chains with a pending «طلب ضم سلسلة» for [companyUID]. One query.
Future<Set<String>> fetchPendingCompanyChainUids({
  required FirebaseFirestore firestore,
  required String companyUID,
}) async {
  final co = companyUID.trim();
  if (co.isEmpty) return const {};
  final snap = await firestore
      .collection(kCompanyChainRequestsCollection)
      .where('companyUID', isEqualTo: co)
      .where('status', isEqualTo: 'pending')
      .get();
  return {
    for (final d in snap.docs)
      if ((d.data()['organizationUID'] ?? '').toString().trim().isNotEmpty)
        (d.data()['organizationUID'] as Object).toString().trim(),
  };
}

/// Writes one pending request per chain in one batch. Returns the batch id.
Future<String> submitCompanyChainRequests({
  required FirebaseFirestore firestore,
  required Delegate supervisor,
  required String companyUID,
  required String companyName,
  required List<CompanyChainOption> chains,
}) async {
  final co = companyUID.trim();
  if (co.isEmpty) throw StateError('companyUID is empty');
  final picked = [
    for (final c in chains)
      if (!c.joined) c,
  ];
  if (picked.isEmpty) throw StateError('no chains');
  if (picked.length > kCompanyChainRequestBatchLimit) {
    throw StateError('too many chains in one send');
  }
  final col = firestore.collection(kCompanyChainRequestsCollection);
  final batchId = col.doc().id;
  // Each create costs 2 exists() in the rules and a batch may use about 20
  // lookups, so send in chunks of [kCompanyChainRequestsPerCommit].
  for (var i = 0; i < picked.length; i += kCompanyChainRequestsPerCommit) {
    final part = picked.sublist(
      i,
      i + kCompanyChainRequestsPerCommit > picked.length
          ? picked.length
          : i + kCompanyChainRequestsPerCommit,
    );
    await _commitRequests(firestore, col, part, picked.length, batchId, co, companyName, supervisor);
  }
  CompanyChainCatalog.clear(co);
  return batchId;
}

const int kCompanyChainRequestsPerCommit = 8;

Future<void> _commitRequests(
  FirebaseFirestore firestore,
  CollectionReference<Map<String, dynamic>> col,
  List<CompanyChainOption> part,
  int total,
  String batchId,
  String co,
  String companyName,
  Delegate supervisor,
) async {
  final picked = part;
  final batch = firestore.batch();
  for (final c in picked) {
    batch.set(col.doc(), {
      'requestType': 'company_join_chain',
      'status': 'pending',
      'batchId': batchId,
      'batchSize': total,
      'companyUID': co,
      'companyName': companyName,
      'organizationUID': c.uid,
      'organizationName': c.name,
      'supervisorUid': supervisor.uid,
      'supervisorName': supervisor.fullName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/// A «طلب ضم سلسلة» row for the approval panel.
class CompanyChainRequest {
  const CompanyChainRequest({
    required this.id,
    required this.status,
    required this.companyUID,
    required this.companyName,
    required this.organizationUID,
    required this.organizationName,
    required this.supervisorUid,
    required this.supervisorName,
    required this.batchId,
    this.createdAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  final String id;
  final String status;
  final String companyUID;
  final String companyName;
  final String organizationUID;
  final String organizationName;
  final String supervisorUid;
  final String supervisorName;
  final String batchId;
  final DateTime? createdAt;
  final String? reviewedBy;
  final String? rejectionReason;

  bool get isPending => status == 'pending';

  factory CompanyChainRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    String s(String k) => (d[k] ?? '').toString();
    final created = d['createdAt'];
    return CompanyChainRequest(
      id: doc.id,
      status: s('status'),
      companyUID: s('companyUID'),
      companyName: s('companyName'),
      organizationUID: s('organizationUID'),
      organizationName: s('organizationName'),
      supervisorUid: s('supervisorUid'),
      supervisorName: s('supervisorName'),
      batchId: s('batchId'),
      createdAt: created is Timestamp ? created.toDate() : null,
      reviewedBy: d['reviewedBy']?.toString(),
      rejectionReason: d['rejectionReason']?.toString(),
    );
  }
}

/// Pending «طلب ضم سلسلة» docs the reviewer may decide on: everything for
/// super admin / technical support, only their own chain for a chain admin.
Stream<List<CompanyChainRequest>> watchPendingCompanyChainRequests({
  required FirebaseFirestore firestore,
  required Delegate reviewer,
}) {
  Query<Map<String, dynamic>> q = firestore
      .collection(kCompanyChainRequestsCollection)
      .where('status', isEqualTo: 'pending');
  if (reviewer.role == UserRole.organizationAdmin) {
    q = q.where('organizationUID', isEqualTo: reviewer.organizationUID.trim());
  }
  return q.snapshots().map((s) {
    final list = s.docs.map(CompanyChainRequest.fromDoc).toList();
    list.sort((a, b) {
      final c = a.companyName.compareTo(b.companyName);
      return c != 0 ? c : a.organizationName.compareTo(b.organizationName);
    });
    return list;
  });
}

bool canReviewCompanyChainRequests(Delegate reviewer) =>
    reviewer.role == UserRole.superAdmin ||
    reviewer.role == UserRole.technicalSupport ||
    reviewer.role == UserRole.organizationAdmin;

const String kCompanyChainUnavailableMessage =
    'السلسلة غير متاحة (غير موجودة أو مخفية). ارفض الطلب.';

/// Approves one request: re-checks the chain, registers the company in it
/// (idempotent, the requesting supervisor becomes an admin there), then
/// marks the request approved. The Cloud Function then links every active
/// delegate of the company to the chain.
Future<void> approveCompanyChainRequest({
  required FirebaseFirestore firestore,
  required CompanyChainRequest request,
  required Delegate reviewer,
}) async {
  final bad = await firstInvalidRequestChain(
    firestore: firestore,
    companyUID: request.companyUID,
    orgIds: [request.organizationUID],
  );
  if (bad != null) throw StateError(kCompanyChainUnavailableMessage);
  String supervisorPhone = '';
  try {
    final sup = await firestore.collection('users').doc(request.supervisorUid).get();
    supervisorPhone = (sup.data()?['phoneNumber'] ?? sup.data()?['phone'] ?? '').toString();
  } catch (_) {}
  await ensureCompanyInChains(
    firestore: firestore,
    companyUID: request.companyUID,
    companyName: request.companyName,
    chains: {request.organizationUID: request.organizationName},
    supervisorUid: request.supervisorUid,
    supervisorName: request.supervisorName,
    supervisorPhone: supervisorPhone,
    requestId: request.id,
  );
  await firestore.collection(kCompanyChainRequestsCollection).doc(request.id).update({
    'status': 'approved',
    'reviewedBy': reviewer.fullName,
    'reviewedByUid': reviewer.uid,
    'reviewedAt': FieldValue.serverTimestamp(),
  });
  CompanyChainCatalog.clear(request.companyUID);
}

Future<void> rejectCompanyChainRequest({
  required FirebaseFirestore firestore,
  required CompanyChainRequest request,
  required Delegate reviewer,
  String reason = '',
}) async {
  await firestore.collection(kCompanyChainRequestsCollection).doc(request.id).update({
    'status': 'rejected',
    'reviewedBy': reviewer.fullName,
    'reviewedByUid': reviewer.uid,
    'reviewedAt': FieldValue.serverTimestamp(),
    'rejectionReason': reason,
  });
  CompanyChainCatalog.clear(request.companyUID);
}
