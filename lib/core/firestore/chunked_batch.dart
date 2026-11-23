import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore rejects a WriteBatch with more than 500 writes, and then nothing
/// in it is applied (TAS-81). Commits [items] in batches of at most
/// [chunkSize] writes, calling [write] once per item.
Future<int> commitInChunks<T>(
  FirebaseFirestore firestore,
  Iterable<T> items,
  void Function(WriteBatch batch, T item) write, {
  int chunkSize = 450,
}) async {
  assert(chunkSize > 0 && chunkSize <= 500);
  var batch = firestore.batch();
  var inBatch = 0;
  var commits = 0;
  for (final item in items) {
    write(batch, item);
    inBatch++;
    if (inBatch == chunkSize) {
      await batch.commit();
      commits++;
      batch = firestore.batch();
      inBatch = 0;
    }
  }
  if (inBatch > 0) {
    await batch.commit();
    commits++;
  }
  return commits;
}

/// Penalties (company field: `companyId`) that follow a rule by title. A company-scoped editor only touches
/// its own company's penalties (TAS-81); global roles pass an empty
/// [companyUID] and keep the cross-company sync.
Query<Map<String, dynamic>> penaltiesWithTitle(
  FirebaseFirestore firestore,
  String title, {
  String companyUID = '',
}) {
  Query<Map<String, dynamic>> q = firestore
      .collection('penalties')
      .where('title', isEqualTo: title.trim());
  if (companyUID.trim().isNotEmpty) {
    q = q.where('companyId', isEqualTo: companyUID.trim());
  }
  return q;
}
