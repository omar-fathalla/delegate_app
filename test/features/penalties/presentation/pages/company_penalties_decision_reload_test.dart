// TAS-266: after a branches-marketing manager approves or rejects a penalty
// the page used to go blank (no case for PenaltyActionSuccessState, no
// reload). It now keeps the list, confirms, and reloads.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPenaltyBloc extends MockBloc<PenaltyEvent, PenaltyState>
    implements PenaltyBloc {}

Delegate _bmm() => Delegate(
      uid: 'seed-fake-bmm',
      firstName: 'مدير',
      middleName: '',
      lastName: 'وهمي',
      fullName: 'مدير تسويق وهمي',
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '01000000902',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      paymentAmount: 0,
      birthDate: DateTime(1990),
      organizationUID: 'seed-fake-org',
      organizationName: 'Fake Org',
      companyUID: '',
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
      role: UserRole.branchesMarketingManager,
    );

PenaltyEntity _penalty() => PenaltyEntity(
      penaltyId: 'seed-fake-pen-1',
      companyId: 'seed-fake-co',
      companyName: 'شركة وهمية',
      createdById: 'seed',
      createdByName: 'تسويق وهمي',
      title: 'مخالفة وهمية للاعتماد',
      category: ViolationCategory.dataMissing,
      incidentDescription: 'وهمي',
      fineAmount: 100,
      currency: 'EGP',
      status: PenaltyStatus.pendingBranchesMarketing,
      evidenceFiles: const [],
      organizationId: 'seed-fake-org',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

void main() {
  setUpAll(() => registerFallbackValue(const LoadAllPenaltiesEvent()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('decision success keeps the list, confirms and reloads', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = _MockPenaltyBloc();
    final states = StreamController<PenaltyState>();
    addTearDown(states.close);
    final loaded = PenaltyLoadedState(penalties: [_penalty()], totalFineAmount: 100, deductedAmount: 0);
    whenListen(bloc, states.stream, initialState: loaded);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar'),
      home: BlocProvider<PenaltyBloc>.value(
        value: bloc,
        child: CompanyPenaltiesSettingsPage(delegate: _bmm()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('مخالفة وهمية للاعتماد'), findsWidgets);
    final before = verify(() => bloc.add(captureAny())).captured
        .whereType<LoadCompanyPenaltiesEvent>().length;

    states.add(const PenaltyActionSuccessState('تم تحديث حالة المخالفة بنجاح.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تم تحديث حالة المخالفة بنجاح.'), findsOneWidget);
    expect(find.textContaining('مخالفة وهمية للاعتماد'), findsWidgets);
    final reloads = verify(() => bloc.add(captureAny())).captured.whereType<LoadCompanyPenaltiesEvent>().toList();
    expect(reloads.length, greaterThanOrEqualTo(1));
    expect(before, 1);
    expect(reloads.last.organizationId, 'seed-fake-org');
  });
}
