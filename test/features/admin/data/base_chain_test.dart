import 'package:delegate_app/features/admin/data/base_chain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-254: the base (free) chain every new delegate is registered under.
void main() {
  test('first non-empty id from freeChainOrgUids', () {
    expect(baseChainIdFromConfig(null), isNull);
    expect(baseChainIdFromConfig({}), isNull);
    expect(baseChainIdFromConfig({'freeChainOrgUids': 'x'}), isNull);
    expect(baseChainIdFromConfig({'freeChainOrgUids': ['', '  ', 'f1', 'f2']}), 'f1');
  });

  test('loads id and name; null when not configured', () async {
    final db = FakeFirebaseFirestore();
    expect(await loadBaseChain(db), isNull);
    await db.doc('config/subscriptions').set({'freeChainOrgUids': ['org-f']});
    await db.doc('organizations/org-f').set({'name': 'فتح الله ماركت'});
    final base = await loadBaseChain(db);
    expect(base?.uid, 'org-f');
    expect(base?.name, 'فتح الله ماركت');
  });
}
