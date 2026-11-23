// TAS-81: batches over 500 writes and the company filter on title sync.
import 'package:delegate_app/core/firestore/chunked_batch.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commits 1001 writes in 3 batches and applies all of them', () async {
    final db = FakeFirebaseFirestore();
    final ids = List.generate(1001, (i) => 'd$i');
    final commits = await commitInChunks(db, ids, (b, id) {
      b.set(db.doc('items/$id'), {'n': 1});
    });
    expect(commits, 3);
    expect((await db.collection('items').get()).docs.length, 1001);
  });

  test('no items, no commit', () async {
    final db = FakeFirebaseFirestore();
    expect(await commitInChunks<String>(db, const [], (b, _) {}), 0);
  });

  test('penaltiesWithTitle filters by company for a company editor only', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('penalties/a').set({'title': 'تأخير', 'companyId': 'c1'});
    await db.doc('penalties/b').set({'title': 'تأخير', 'companyId': 'c2'});
    await db.doc('penalties/c').set({'title': 'غياب', 'companyId': 'c1'});
    final scoped = await penaltiesWithTitle(db, ' تأخير ', companyUID: 'c1').get();
    expect(scoped.docs.map((d) => d.id), ['a']);
    final global = await penaltiesWithTitle(db, 'تأخير').get();
    expect(global.docs.map((d) => d.id).toSet(), {'a', 'b'});
  });
}
