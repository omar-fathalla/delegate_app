import 'package:delegate_app/features/penalties/presentation/widgets/supervisor_penalty_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _d({
  String uid = 'd1',
  DelegatePosition position = DelegatePosition.promoter,
  String companyUID = 'c1',
}) => Delegate(
  uid: uid,
  firstName: 'a',
  middleName: 'b',
  lastName: 'c',
  fullName: 'مندوب $uid',
  nationalityID: '1',
  motherName: 'm',
  city: 'cairo',
  phoneNumber: '010',
  gender: DelegateGender.male,
  position: position,
  birthDate: DateTime(1990),
  organizationUID: 'o1',
  organizationName: 'O',
  companyUID: companyUID,
  companyName: 'C',
  status: DelegateStatus.active,
  delegatePublicId: 'p',
  allReceiptCodes: const [],
  createdAt: DateTime(2020),
  createdBy: 'x',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.delegate,
  allOrganizationNames: const [],
);

void main() {
  final sup = _d(uid: 's1', position: DelegatePosition.supervisor);

  group('SupervisorPenaltySheet.canAdd (TAS-320)', () {
    test('supervisor on a delegate of its company', () {
      expect(SupervisorPenaltySheet.canAdd(viewer: sup, target: _d()), isTrue);
    });
    test('not on itself, not on another company, not for promoters', () {
      expect(SupervisorPenaltySheet.canAdd(viewer: sup, target: sup), isFalse);
      expect(
        SupervisorPenaltySheet.canAdd(
          viewer: sup,
          target: _d(companyUID: 'c2'),
        ),
        isFalse,
      );
      expect(
        SupervisorPenaltySheet.canAdd(
          viewer: _d(uid: 'p1'),
          target: _d(),
        ),
        isFalse,
      );
      expect(
        SupervisorPenaltySheet.canAdd(viewer: null, target: _d()),
        isFalse,
      );
    });
  });

  testWidgets('validates, then sends the penalty to the callable', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupervisorPenaltySheet(
            delegate: _d(),
            supervisor: sup,
            submitOverride: (p) async => sent = p,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('supervisor_penalty_submit')));
    await tester.pump();
    expect(sent, isNull);
    expect(find.text('اكتب سبب الجزاء'), findsOneWidget);
    expect(find.text('اكتب قيمة أكبر من صفر'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('supervisor_penalty_title')),
      'تأخير عن الوردية',
    );
    await tester.enterText(
      find.byKey(const Key('supervisor_penalty_amount')),
      '50000',
    );
    await tester.tap(find.byKey(const Key('supervisor_penalty_submit')));
    await tester.pump();
    expect(sent, isNull);

    await tester.enterText(
      find.byKey(const Key('supervisor_penalty_amount')),
      '75',
    );
    await tester.tap(find.byKey(const Key('supervisor_penalty_submit')));
    await tester.pump();
    expect(sent, isNotNull);
    expect(sent!['targetDelegateId'], 'd1');
    expect(sent!['companyUID'], 'c1');
    expect(sent!['fineAmount'], 75);
    expect(sent!['category'], 'PROTOCOL_BREACH');
    expect(sent!['title'], 'تأخير عن الوردية');
  });
}
