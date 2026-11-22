import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/utils/penalty_list_scope.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _user(UserRole role, {String company = '', String org = ''}) => Delegate(
      uid: 'u1',
      firstName: 'Fake',
      middleName: '',
      lastName: 'User',
      fullName: 'Fake User',
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      paymentAmount: 0,
      birthDate: DateTime(1990),
      organizationUID: org,
      organizationName: '',
      companyUID: company,
      companyName: '',
      status: DelegateStatus.active,
      delegatePublicId: '',
      allReceiptCodes: const [],
      createdAt: DateTime(2026),
      createdBy: 'seed',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      version: 1,
      documents: const [],
      role: role,
    );

/// TAS-73: which penalties list each role loads, so the rules can prove it.
void main() {
  group('penaltyListEventFor', () {
    test('global staff list everything', () {
      for (final role in [UserRole.superAdmin, UserRole.technicalSupport]) {
        expect(penaltyListEventFor(_user(role, org: 'org_a')), isA<LoadAllPenaltiesEvent>());
      }
    });

    test('company staff list their company only', () {
      for (final role in [UserRole.admin, UserRole.hr, UserRole.accountant, UserRole.marketing]) {
        final e = penaltyListEventFor(_user(role, company: 'co_1', org: 'org_a'));
        expect(e, const LoadCompanyPenaltiesEvent('co_1'), reason: role.name);
      }
    });

    test('org-scoped staff (no company) list their organization', () {
      for (final role in [UserRole.organizationAdmin, UserRole.marketing, UserRole.marketingPromotion]) {
        final e = penaltyListEventFor(_user(role, org: 'org_a'));
        expect(e, const LoadCompanyPenaltiesEvent('', organizationId: 'org_a'), reason: role.name);
      }
    });

    test('companyViewOnly keeps a global user on its company', () {
      final e = penaltyListEventFor(_user(UserRole.superAdmin, company: 'co_1'), companyViewOnly: true);
      expect(e, const LoadCompanyPenaltiesEvent('co_1'));
    });
  });

  group('PenaltyModel.organizationId', () {
    PenaltyModel model({String? org}) => PenaltyModel(
          penaltyId: 'p1',
          companyId: 'co_1',
          companyName: 'Fake Co',
          organizationId: org,
          createdById: 'a1',
          createdByName: 'Admin',
          title: 'Fake',
          category: ViolationCategory.dataMissing,
          incidentDescription: '',
          fineAmount: 50,
          currency: 'EGP',
          status: PenaltyStatus.issued,
          evidenceFiles: const [],
          createdAt: DateTime(2026, 11, 22),
          updatedAt: DateTime(2026, 11, 22),
        );

    test('is written when set and read back', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('penalties/p1').set(model(org: 'org_a').toJson());
      final back = PenaltyModel.fromFirestore(await db.doc('penalties/p1').get());
      expect((await db.doc('penalties/p1').get()).data()!['organizationId'], 'org_a');
      expect(back.organizationId, 'org_a');
      expect(PenaltyModel.fromEntity(back).organizationId, 'org_a');
    });

    test('is left out when unknown (old docs read as null)', () async {
      expect(model().toJson().containsKey('organizationId'), isFalse);
      final db = FakeFirebaseFirestore();
      await db.doc('penalties/p2').set(model().toJson());
      expect(PenaltyModel.fromFirestore(await db.doc('penalties/p2').get()).organizationId, isNull);
    });
  });
}
