import 'package:delegate_app/features/photo_permission/presentation/widgets/company_name_with_code.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('companyCodeFromData prefers companyCodeInOrg', () {
    expect(
      companyCodeFromData({'companyCodeInOrg': '7', 'code': '9'}),
      '7',
    );
    expect(companyCodeFromData({'code': 12}), '12');
    expect(companyCodeFromData({'code': '0'}), isNull);
    expect(companyCodeFromData(null), isNull);
  });

  test('fetchCompanyCode uses the nested path when organizationUID is known', () async {
    final fs = FakeFirebaseFirestore();
    await fs
        .collection('organizations')
        .doc('org_dev_test')
        .collection('companies')
        .doc('co_dev_test')
        .set({'uid': 'co_dev_test', 'companyCodeInOrg': '15'});

    final code = await fetchCompanyCode(
      firestore: fs,
      organizationUID: 'org_dev_test',
      companyUID: 'co_dev_test',
    );
    expect(code, '15');
  });

  test('fetchCompanyCode falls back to collectionGroup filter on uid, not documentId', () async {
    final fs = FakeFirebaseFirestore();
    await fs
        .collection('organizations')
        .doc('org_dev_test')
        .collection('companies')
        .doc('co_dev_test')
        .set({'uid': 'co_dev_test', 'companyCodeInOrg': '15'});

    // Bare id would throw on a real collection-group documentId() query
    // ("odd number of segments"). The fallback filters on the stored uid.
    final code = await fetchCompanyCode(
      firestore: fs,
      organizationUID: '',
      companyUID: 'co_dev_test',
    );
    expect(code, '15');
  });
}
