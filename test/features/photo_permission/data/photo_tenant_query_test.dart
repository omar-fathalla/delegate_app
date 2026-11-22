import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-73: photo lists carry the tenant filter the rules need.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final (org, co) in [('org_a', 'co_a1'), ('org_a', 'co_a2'), ('org_b', 'co_b1')]) {
      final perm = db.doc('organizations/$org/companies/$co/photo_permissions/p_$co');
      await perm.set({'companyUID': co, 'organizationUID': org, 'status': 'pending'});
      await perm.collection('captured_photos').doc('ph_$co').set({
        'companyUID': co,
        'organizationUID': org,
        'delegateUID': 'd_$co',
      });
    }
  });

  Future<List<String>> companies(Future<dynamic> q) async {
    final snap = await q;
    return [for (final d in snap.docs) d.data()['companyUID'] as String]..sort();
  }

  test('company wins over organization', () async {
    expect(
      await companies(photoPermissionsTenantQuery(db, companyUID: 'co_a1', organizationUID: 'org_a').get()),
      ['co_a1'],
    );
    expect(
      await companies(capturedPhotosTenantQuery(db, companyUID: 'co_a1', organizationUID: 'org_a').get()),
      ['co_a1'],
    );
  });

  test('no company: filtered by organization', () async {
    expect(
      await companies(photoPermissionsTenantQuery(db, companyUID: '', organizationUID: 'org_a').get()),
      ['co_a1', 'co_a2'],
    );
    expect(
      await companies(capturedPhotosTenantQuery(db, companyUID: ' ', organizationUID: 'org_a').get()),
      ['co_a1', 'co_a2'],
    );
  });

  test('neither (global staff): unfiltered', () async {
    expect(
      await companies(capturedPhotosTenantQuery(db, companyUID: '', organizationUID: '').get()),
      ['co_a1', 'co_a2', 'co_b1'],
    );
  });

  test('photoListOrgScope keeps the organization except for global staff', () {
    expect(photoListOrgScope(UserRole.superAdmin, 'org_a'), '');
    expect(photoListOrgScope(UserRole.technicalSupport, 'org_a'), '');
    for (final role in [
      UserRole.organizationAdmin,
      UserRole.marketing,
      UserRole.marketingPromotion,
      UserRole.branchesMarketingManager,
      UserRole.hr,
      UserRole.admin,
    ]) {
      expect(photoListOrgScope(role, 'org_a'), 'org_a', reason: role.name);
    }
  });
}
