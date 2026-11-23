import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

/// TAS-51: the rules no longer accept a staff notification carrying only
/// `createdBy`; it must name the sender's own organization or company.
void main() {
  group('penalty notifications carry the sender tenant', () {
    late FakeFirebaseFirestore firestore;

    Future<List<Map<String, dynamic>>> notifications() async =>
        (await firestore.collection('notifications').get())
            .docs
            .map((d) => d.data())
            .toList();

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      await firestore.collection('penalties').doc('pen-1').set({
        'companyId': 'seed-fake-co-a',
        'companyName': 'شركة وهمية',
        'createdById': 'seed-fake-supervisor',
        'createdByName': 'مشرف وهمي',
        'title': 'تأخير',
        'category': 'attendance',
        'incidentDescription': 'وهمي',
        'fineAmount': 50,
        'status': 'pendingBranchesMarketing',
        'targetDelegateId': 'seed-fake-delegate-1',
        'createdAt': DateTime(2026, 11, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 11, 1).toIso8601String(),
      });
    });

    test('org-wide manager (no company) stamps its own organization', () async {
      await firestore.collection('users').doc('seed-fake-bmm').set({
        'role': 'branches_marketing',
        'organizationUID': 'seed-fake-org',
      });
      final ds = PenaltyRemoteDataSourceImpl(
        firestore: firestore,
        storage: _MockStorage(),
        currentUid: () => 'seed-fake-bmm',
      );
      await ds.updatePenaltyStatus(
        penaltyId: 'pen-1',
        status: PenaltyStatus.pendingGeneralManager,
        reviewerName: 'مدير وهمي',
      );
      final sent = await notifications();
      expect(sent, isNotEmpty);
      for (final n in sent) {
        expect(n['createdBy'], 'seed-fake-bmm');
        expect(n['organizationUID'], 'seed-fake-org');
        expect(n.containsKey('companyUID'), isFalse);
      }
    });

    test('company staff stamp both their organization and company', () async {
      await firestore.collection('users').doc('seed-fake-ca').set({
        'role': 'company-admin',
        'organizationUID': 'seed-fake-org',
        'companyUID': 'seed-fake-co-a',
      });
      final ds = PenaltyRemoteDataSourceImpl(
        firestore: firestore,
        storage: _MockStorage(),
        currentUid: () => 'seed-fake-ca',
      );
      await ds.updatePenaltyStatus(
        penaltyId: 'pen-1',
        status: PenaltyStatus.pendingGeneralManager,
        reviewerName: 'أدمن وهمي',
      );
      final sent = await notifications();
      expect(sent, isNotEmpty);
      expect(sent.every((n) => n['companyUID'] == 'seed-fake-co-a'), isTrue);
      expect(sent.every((n) => n['organizationUID'] == 'seed-fake-org'), isTrue);
    });
  });

  group('DeviceBindingService.callerTenantFields', () {
    test('keeps the caller own org and company, drops empty and "all"', () {
      expect(
        DeviceBindingService.callerTenantFields(
            {'organizationUID': 'org-1', 'companyUID': 'co-1'}),
        {'organizationUID': 'org-1', 'companyUID': 'co-1'},
      );
      expect(
        DeviceBindingService.callerTenantFields(
            {'organizationId': 'org-2', 'companyUID': ''}),
        {'organizationUID': 'org-2'},
      );
      expect(
        DeviceBindingService.callerTenantFields({'organizationUID': 'all'}),
        isEmpty,
      );
    });
  });
}
