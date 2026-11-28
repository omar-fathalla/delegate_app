import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/penalties/presentation/widgets/penalty_response_panel.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _MockBloc extends MockBloc<PenaltyEvent, PenaltyState>
    implements PenaltyBloc {}

/// TAS-365: the dispute flow on the penalty card. Fake data only.
void main() {
  final issued = DateTime(2026, 11, 20, 10);
  PenaltyEntity penalty(PenaltyStatus status,
          {DateTime? disputedAt, String? reason, String? resolution}) =>
      PenaltyEntity(
        penaltyId: 'p1',
        companyId: 'c1',
        companyName: 'Fake Co',
        organizationId: 'o1',
        createdById: 's1',
        createdByName: 'Fake Supervisor',
        title: 'تأخير',
        category: ViolationCategory.other,
        incidentDescription: '',
        fineAmount: 100,
        status: status,
        targetDelegateId: 'd1',
        createdAt: issued,
        updatedAt: issued,
        issuedAt: issued,
        disputedAt: disputedAt,
        disputeReason: reason,
        disputeResolution: resolution,
        disputeResolutionReason: resolution == null ? null : 'الدليل واضح',
      );
  Delegate person(UserRole role) => Delegate(
        uid: 'd1',
        firstName: 'Fake',
        middleName: '',
        lastName: 'User',
        fullName: 'Fake User',
        nationalityID: '00000000000000',
        motherName: '',
        city: '',
        phoneNumber: '01000000000',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        paymentAmount: 0.0,
        birthDate: DateTime(1990, 1, 1),
        organizationUID: 'o1',
        organizationName: 'Org',
        companyUID: 'c1',
        companyName: 'Fake Co',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-1',
        allReceiptCodes: const [],
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'admin',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        version: 1,
        documents: const [],
        role: role,
      );

  late _MockBloc bloc;
  setUpAll(() => registerFallbackValue(
      const RespondToPenaltyEvent(penaltyId: 'x', action: PenaltyResponseAction.acknowledge)));
  setUp(() {
    bloc = _MockBloc();
    when(() => bloc.state).thenReturn(PenaltyInitialState());
  });

  Future<void> pump(WidgetTester t, PenaltyEntity p, Delegate d, DateTime now) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BlocProvider<PenaltyBloc>.value(
            value: bloc,
            child: PenaltyResponsePanel(
                penalty: p, currentDelegate: d, now: () => now),
          ),
        ),
      ));

  testWidgets('delegate: acknowledge and dispute inside the window',
      (t) async {
    await pump(t, penalty(PenaltyStatus.issued), person(UserRole.delegate),
        issued.add(const Duration(days: 1)));
    expect(find.byKey(const ValueKey('penalty-acknowledge')), findsOneWidget);
    expect(find.byKey(const ValueKey('penalty-dispute')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('penalty-acknowledge')));
    final ev = verify(() => bloc.add(captureAny())).captured.single
        as RespondToPenaltyEvent;
    expect(ev.action, PenaltyResponseAction.acknowledge);
  });

  testWidgets('delegate: dispute needs a reason', (t) async {
    await pump(t, penalty(PenaltyStatus.acknowledged),
        person(UserRole.delegate), issued.add(const Duration(days: 2)));
    expect(find.byKey(const ValueKey('penalty-acknowledge')), findsNothing);
    await t.tap(find.byKey(const ValueKey('penalty-dispute')));
    await t.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('penalty-reason-confirm'));
    expect(t.widget<TextButton>(confirm).onPressed, isNull);
    await t.enterText(
        find.byKey(const ValueKey('penalty-reason-field')), 'كنت في إجازة');
    await t.pump();
    await t.tap(confirm);
    await t.pumpAndSettle();
    final ev = verify(() => bloc.add(captureAny())).captured.single
        as RespondToPenaltyEvent;
    expect(ev.action, PenaltyResponseAction.dispute);
    expect(ev.reason, 'كنت في إجازة');
  });

  testWidgets('delegate: no dispute after 3 days', (t) async {
    await pump(t, penalty(PenaltyStatus.acknowledged),
        person(UserRole.delegate), issued.add(const Duration(days: 3, minutes: 1)));
    expect(find.byKey(const ValueKey('penalty-dispute')), findsNothing);
  });

  testWidgets('delegate: open dispute shows message 8.3, no buttons',
      (t) async {
    await pump(
        t,
        penalty(PenaltyStatus.disputed,
            disputedAt: issued, reason: 'كنت في إجازة'),
        person(UserRole.delegate),
        issued.add(const Duration(days: 1)));
    expect(find.textContaining('مستنيين رد الإدارة'), findsOneWidget);
    expect(find.byKey(const ValueKey('penalty-dispute')), findsNothing);
  });

  testWidgets('delegate: rejected dispute shows the reason, no second dispute',
      (t) async {
    await pump(
        t,
        penalty(PenaltyStatus.issued,
            disputedAt: issued, reason: 'x', resolution: 'upheld'),
        person(UserRole.delegate),
        issued.add(const Duration(days: 1)));
    expect(find.textContaining('اعتراضك اترفض'), findsOneWidget);
    expect(find.byKey(const ValueKey('penalty-dispute')), findsNothing);
  });

  testWidgets('chain admin decides a dispute with a reason', (t) async {
    await pump(
        t,
        penalty(PenaltyStatus.disputed, disputedAt: issued, reason: 'غلط'),
        person(UserRole.organizationAdmin),
        issued);
    expect(find.byKey(const ValueKey('penalty-uphold')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('penalty-cancel')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const ValueKey('penalty-reason-field')), 'كان في إجازة');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('penalty-reason-confirm')));
    await t.pumpAndSettle();
    final ev = verify(() => bloc.add(captureAny())).captured.single
        as RespondToPenaltyEvent;
    expect(ev.action, PenaltyResponseAction.cancelPenalty);
  });

  testWidgets('HR sees no decision buttons', (t) async {
    await pump(
        t,
        penalty(PenaltyStatus.disputed, disputedAt: issued, reason: 'غلط'),
        person(UserRole.hr),
        issued);
    expect(find.byKey(const ValueKey('penalty-uphold')), findsNothing);
  });
}
