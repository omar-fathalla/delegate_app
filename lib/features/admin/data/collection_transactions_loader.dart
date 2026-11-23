import 'package:cloud_firestore/cloud_firestore.dart';

/// Loads every recorded collection transaction across all months
/// (`monthly_collections/{period}/transactions`), newest first.
///
/// TAS-259: the collections screen sums ALL transactions (cumulative totals)
/// and lists all of them (paged in memory), so every transaction document is
/// needed; the month subcollections are now read in parallel instead of one
/// after another. A `collectionGroup('transactions')` query is not used: it
/// would also match `wallets/*/transactions`, and the rules have no
/// recursive `transactions` match (adding one would widen wallet reads).
Future<List<Map<String, dynamic>>> loadAllCollectionTransactions(
  FirebaseFirestore firestore,
) async {
  final monthsSnapshot = await firestore.collection('monthly_collections').get();
  final perMonth = await Future.wait(monthsSnapshot.docs.map((mDoc) async {
    final txSnapshot = await mDoc.reference.collection('transactions').get();
    return txSnapshot.docs.map((doc) {
      final d = doc.data();
      return <String, dynamic>{
        'id': doc.id,
        'periodKey': d['periodKey'] ?? mDoc.id,
        ...d,
      };
    }).toList();
  }));

  final all = <Map<String, dynamic>>[for (final list in perMonth) ...list];
  all.sort((a, b) {
    final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
    final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
    return bTime.compareTo(aTime); // Latest first
  });
  return all;
}
