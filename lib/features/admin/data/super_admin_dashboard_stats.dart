import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-cost helpers for the super-admin dashboard (TAS-89).
///
/// The dashboard used to keep two realtime listeners open while its tab
/// stayed alive: one on every pending `delegate_requests` doc and one on
/// every delegate in `collectionGroup('delegates')`. Each listener re-read a
/// document on every change, only to show a few numbers.

/// Number of pending delegate subscription requests.
///
/// Same filter as the old listener (`status == 'pending'`), but as a
/// `count()` aggregate: one read per 1000 matching docs instead of one read
/// per doc plus one per change.
Future<int> countPendingDelegateRequests(FirebaseFirestore firestore) async {
  final snap = await firestore
      .collection('delegate_requests')
      .where('status', isEqualTo: 'pending')
      .count()
      .get();
  return snap.count ?? 0;
}

/// Electronic-receipt and deduction counters shown on the dashboard.
class SuperAdminDelegateStats {
  final int withImage;
  final int emptyOrMissing;
  final int approved;
  final int deducted;
  final int total;

  const SuperAdminDelegateStats({
    required this.withImage,
    required this.emptyOrMissing,
    required this.approved,
    required this.deducted,
    required this.total,
  });
}

/// The delegates query the dashboard counts over (unchanged filter: an
/// organization-scoped super admin only sees its organization).
Query<Map<String, dynamic>> superAdminDelegatesQuery(
  FirebaseFirestore firestore,
  String organizationUID,
) {
  Query<Map<String, dynamic>> query = firestore.collectionGroup('delegates');
  if (organizationUID.isNotEmpty) {
    query = query.where('organizationUID', isEqualTo: organizationUID);
  }
  return query;
}

/// One-shot read of the delegate counters.
///
/// The receipt counters depend on entries inside each delegate's
/// `documents` array, which a `count()` aggregate cannot filter on, so this
/// still reads the matching delegates, but once per open / pull-to-refresh
/// instead of through a listener that re-reads on every delegate change.
Future<SuperAdminDelegateStats> loadSuperAdminDelegateStats(
  FirebaseFirestore firestore,
  String organizationUID,
) async {
  final snap = await superAdminDelegatesQuery(firestore, organizationUID).get();
  return computeSuperAdminDelegateStats(snap.docs, organizationUID);
}

const _electronicReceiptKeys = {
  'electronicpaymentreceipt',
  'electronic_payment_receipt',
  'electronicreceipt',
  'electronic_receipt',
};

/// Pure tally of delegate docs (same rules as the old listener callback).
SuperAdminDelegateStats computeSuperAdminDelegateStats(
  Iterable<QueryDocumentSnapshot<Object?>> docs,
  String organizationUID,
) {
  int withImage = 0;
  int emptyOrMissing = 0;
  int approved = 0;
  int deducted = 0;
  int total = 0;

  for (final doc in docs) {
    final pathParts = doc.reference.path.split('/');
    final orgUid = pathParts.length > 1 ? pathParts[1] : '';
    if (organizationUID.isNotEmpty && orgUid != organizationUID) {
      continue;
    }

    total++;
    final data = doc.data() as Map<String, dynamic>? ?? {};
    if (data['isDeductedFromCompany'] == true) {
      deducted++;
    }

    final documentsList = data['documents'] as List? ?? [];
    Map<String, dynamic>? electronicDoc;

    for (final docItem in documentsList) {
      if (docItem is Map<String, dynamic>) {
        final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
        if (_electronicReceiptKeys.contains(key)) {
          electronicDoc = docItem;
          break;
        }
      }
    }

    if (electronicDoc != null) {
      final url = (electronicDoc['documentURL']?.toString() ??
              electronicDoc['secondaryURL']?.toString() ??
              '')
          .trim();
      final status =
          electronicDoc['documentStatus']?.toString().toLowerCase() ?? '';

      if (url.isNotEmpty) {
        withImage++;
        if (status == 'approved') {
          approved++;
        }
      } else {
        emptyOrMissing++;
      }
    } else {
      emptyOrMissing++;
    }
  }

  return SuperAdminDelegateStats(
    withImage: withImage,
    emptyOrMissing: emptyOrMissing,
    approved: approved,
    deducted: deducted,
    total: total,
  );
}
