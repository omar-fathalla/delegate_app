// TAS-259: the branch display cache, the HR attendance screens and the
// fake-GPS audit log share ONE full `branches` read per session.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingFirestore extends FakeFirebaseFirestore {
  int branchCollectionCalls = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'branches') branchCollectionCalls++;
    return super.collection(path);
  }
}

void main() {
  late _CountingFirestore fs;

  setUp(() async {
    fs = _CountingFirestore();
    await fs.collection('branches').doc('b1').set({
      'branchName': 'Maadi',
      'displayNameAr': 'المعادي',
      'organizationUID': 'org1',
    });
    await fs.collection('branches').doc('b2').set({
      'branchName': 'Nasr City',
      'organizationUID': 'org2',
    });
    fs.branchCollectionCalls = 0;
    BranchesSessionCache.invalidate();
    BranchesSessionCache.debugSessionKey = () => 'hr-1';
    BranchDisplayCache.debugFirestore = () => fs;
    BranchDisplayCache.instance.debugReset();
  });

  tearDown(() {
    BranchesSessionCache.invalidate();
    BranchesSessionCache.debugSessionKey = null;
    BranchDisplayCache.debugFirestore = null;
    BranchDisplayCache.instance.debugReset();
  });

  test('concurrent ensureLoaded calls share one in-flight read', () async {
    await Future.wait([
      BranchDisplayCache.instance.ensureLoaded(),
      BranchDisplayCache.instance.ensureLoaded(),
      BranchDisplayCache.instance.ensureLoaded(),
    ]);
    expect(fs.branchCollectionCalls, 1);
    expect(BranchDisplayCache.instance.displayName('Maadi'), 'المعادي');
    expect(BranchDisplayCache.instance.displayName('b1'), 'المعادي');
    // No Arabic name: the original name is shown, unchanged.
    expect(BranchDisplayCache.instance.displayName('Nasr City'), 'Nasr City');
  });

  test('display cache and a screen loading branches read the list once',
      () async {
    await BranchDisplayCache.instance.ensureLoaded();
    // What the HR attendance tab / detail screen / audit log now call.
    final docs = await BranchesSessionCache.load(fs);
    expect(fs.branchCollectionCalls, 1);
    // Same full list as a plain collection read (no narrowing of data).
    final plain = await fs.collection('branches').get();
    expect(docs.map((d) => d.id).toSet(), plain.docs.map((d) => d.id).toSet());
  });

  test('registerDocs registers every branch like registerSnapshot', () async {
    final snap = await fs.collection('branches').get();
    BranchDisplayCache.instance.registerDocs(snap.docs);
    expect(BranchDisplayCache.instance.isLoaded, isTrue);
    expect(
      BranchDisplayCache.instance.infoFor('maadi')?.organizationUID,
      'org1',
    );
    expect(
      BranchDisplayCache.instance.infoFor('b2')?.organizationUID,
      'org2',
    );
  });
}
