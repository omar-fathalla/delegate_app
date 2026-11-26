import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/home/presentation/pages/main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tDelegate;

  setUpAll(() {
    tDelegate = Delegate(
      uid: 'delegate123',
      firstName: 'Test',
      middleName: 'M',
      lastName: 'User',
      fullName: 'Test M User',
      nationalityID: '12345678901234',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '+201000000000',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org1',
      companyUID: 'comp1',
      organizationName: 'Test Org',
      companyName: 'Test Comp',
      status: DelegateStatus.active,
      delegatePublicId: 'pub123',
      allReceiptCodes: const [],
      createdAt: DateTime.now(),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.delegate,
    );
  });

  testWidgets('MainScreen should initialize successfully', (WidgetTester tester) async {
    // We only test constructor to avoid full DI container setup for UI tests
    final widget = MainScreen(delegate: tDelegate);
    expect(widget.delegate, equals(tDelegate));
  });

  group('freshProfileFor (TAS-384)', () {
    Delegate copy(Delegate d, {String? org, String? co, String? orgUid}) =>
        Delegate(
          uid: d.uid,
          firstName: d.firstName,
          middleName: d.middleName,
          lastName: d.lastName,
          fullName: d.fullName,
          nationalityID: d.nationalityID,
          motherName: d.motherName,
          city: d.city,
          phoneNumber: d.phoneNumber,
          gender: d.gender,
          position: d.position,
          birthDate: d.birthDate,
          organizationUID: orgUid ?? d.organizationUID,
          companyUID: d.companyUID,
          organizationName: org ?? d.organizationName,
          companyName: co ?? d.companyName,
          status: d.status,
          delegatePublicId: d.delegatePublicId,
          allReceiptCodes: d.allReceiptCodes,
          createdAt: d.createdAt,
          createdBy: d.createdBy,
          hasPendingUpdate: d.hasPendingUpdate,
          isDeductedFromCompany: d.isDeductedFromCompany,
          isPrinted: d.isPrinted,
          isProfileComplete: d.isProfileComplete,
          numberOfDocuments: d.numberOfDocuments,
          paymentAmount: d.paymentAmount,
          version: d.version,
          documents: d.documents,
          role: d.role,
        );

    test('takes the server copy when the cached names were empty', () {
      final cached = copy(tDelegate, org: '', co: '');
      final server = copy(tDelegate, org: 'Org', co: 'Co');
      expect(freshProfileFor(cached, [server]), same(server));
    });

    test('nothing when the names are the same', () {
      expect(freshProfileFor(tDelegate, [copy(tDelegate)]),
          isNull);
    });

    test('ignores copies in another organization', () {
      final other = copy(tDelegate, orgUid: 'org2', org: 'Other');
      expect(freshProfileFor(tDelegate, [other]), isNull);
    });

    test('an empty server name never clears a cached one', () {
      final server = copy(tDelegate, org: '', co: '');
      expect(freshProfileFor(tDelegate, [server]), isNull);
    });
  });
}
