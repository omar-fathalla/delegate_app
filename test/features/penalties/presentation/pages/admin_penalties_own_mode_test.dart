import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPenaltyBloc extends MockBloc<PenaltyEvent, PenaltyState>
    implements PenaltyBloc {}

Delegate _hr() => Delegate(
  uid: 'seed-fake-hr-006',
  firstName: 'موارد',
  middleName: '',
  lastName: 'وهمي',
  fullName: 'موارد وهمي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000006',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  paymentAmount: 0,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-hr-org',
  organizationName: 'Fake Test Organization',
  companyUID: 'seed-fake-co-alpha',
  companyName: 'Fake Company Alpha',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  version: 1,
  documents: const [],
  role: UserRole.hr,
);

PenaltyEntity _penalty({required bool confidential}) => PenaltyEntity(
  penaltyId: 'seed-fake-pen-1',
  companyId: 'seed-fake-co-alpha',
  companyName: 'Fake Company Alpha',
  createdById: 'seed-fake-supervisor',
  createdByName: 'مشرف وهمي',
  title: 'مخالفة وهمية سرية',
  category: ViolationCategory.dataMissing,
  incidentDescription: 'وهمي',
  fineAmount: 75,
  currency: 'EGP',
  status: PenaltyStatus.issued,
  evidenceFiles: const [],
  targetDelegateId: 'seed-fake-hr-006',
  targetDelegateName: 'موارد وهمي',
  isConfidential: confidential,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

void main() {
  setUpAll(() => registerFallbackValue(const LoadAllPenaltiesEvent()));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_MockPenaltyBloc> pump(
    WidgetTester tester, {
    required bool own,
    bool company = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bloc = _MockPenaltyBloc();
    final loaded = PenaltyLoadedState(
      penalties: [_penalty(confidential: true)],
      totalFineAmount: 75,
      deductedAmount: 0,
    );
    whenListen(bloc, const Stream<PenaltyState>.empty(), initialState: loaded);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<PenaltyBloc>.value(
            value: bloc,
            child: AdminPenaltiesListPage(
              adminDelegate: _hr(),
              ownPenaltiesOnly: own,
              companyViewOnly: company,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return bloc;
  }

  testWidgets('own mode loads only the user\'s penalties, read-only', (
    tester,
  ) async {
    final bloc = await pump(tester, own: true);
    final events = verify(() => bloc.add(captureAny())).captured;
    expect(events.whereType<LoadOwnPenaltiesEvent>(), hasLength(1));
    expect(
      (events.single as LoadOwnPenaltiesEvent).user.uid,
      'seed-fake-hr-006',
    );
    expect(events.whereType<LoadAllPenaltiesEvent>(), isEmpty);
    expect(events.whereType<LoadCompanyPenaltiesEvent>(), isEmpty);
    expect(find.text('مخالفاتي وغراماتي'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('مخالفة وهمية سرية'), findsWidgets);
  });

  testWidgets('without own mode an HR user still gets the old behaviour', (
    tester,
  ) async {
    final bloc = await pump(tester, own: false);
    final events = verify(() => bloc.add(captureAny())).captured;
    expect(events.whereType<LoadOwnPenaltiesEvent>(), isEmpty);
    expect(events.whereType<LoadAllPenaltiesEvent>(), hasLength(1));
    expect(find.text('سجل المخالفات والغرامات'), findsOneWidget);
    expect(find.text('مخالفة وهمية سرية'), findsNothing);
  });

  testWidgets('company view loads the company list, read-only (TAS-156)', (
    tester,
  ) async {
    final bloc = await pump(tester, own: false, company: true);
    final events = verify(() => bloc.add(captureAny())).captured;
    expect(events.whereType<LoadOwnPenaltiesEvent>(), isEmpty);
    expect(events.whereType<LoadAllPenaltiesEvent>(), isEmpty);
    final company = events.whereType<LoadCompanyPenaltiesEvent>().toList();
    expect(company, hasLength(1));
    expect(company.single.companyId, 'seed-fake-co-alpha');
    expect(find.text('سجل المخالفات والغرامات'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    // Confidential penalties stay limited to the roles allowed to see them.
    expect(find.text('مخالفة وهمية سرية'), findsNothing);
  });
}
