import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:delegate_app/features/feedback/presentation/pages/submit_feedback_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-358: feedback type is single-select FilterChips (no ChoiceChip), the
/// message field is outlined from the theme with a label, and a sent
/// feedback shows a snackbar (no «شكرًا لك!» dialog). Fake data only.
class _MockFeedbackBloc extends MockBloc<FeedbackEvent, FeedbackState>
    implements FeedbackBloc {}

final _user = Delegate(
  uid: 'seed-fake-u',
  firstName: 'مندوب',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مندوب تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1995),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
  companyUID: 'seed-fake-co',
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2024),
  createdBy: 'seed',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
);

void main() {
  Future<(StreamController<FeedbackState>, AppLocalizations)> pump(
    WidgetTester t,
  ) async {
    final states = StreamController<FeedbackState>();
    addTearDown(states.close);
    final bloc = _MockFeedbackBloc();
    whenListen(bloc, states.stream, initialState: FeedbackInitial());
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider<FeedbackBloc>.value(
                    value: bloc,
                    child: SubmitFeedbackScreen(
                      delegate: _user,
                      showAppBar: false,
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return (states, lookupAppLocalizations(const Locale('ar')));
  }

  testWidgets('type is FilterChips and the message has a label', (t) async {
    final (_, l10n) = await pump(t);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilterChip), findsNWidgets(FeedbackType.values.length));
    final field = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('feedback_message')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.labelText, l10n.yourMessage);
    expect(field.decoration?.filled, isNot(true));
  });

  testWidgets('sent: a snackbar, no dialog, the page closes', (t) async {
    final (states, l10n) = await pump(t);
    states.add(FeedbackSubmitted());
    await t.pump();
    await t.pump();
    expect(find.byType(AlertDialog), findsNothing);
    // Both scaffolds show it while the page slides out.
    expect(find.text(l10n.feedbackReceived), findsWidgets);
    await t.pumpAndSettle();
    expect(find.byType(SubmitFeedbackScreen), findsNothing);
    // It stays on the app's messenger after the page closed.
    expect(find.text(l10n.feedbackReceived), findsOneWidget);
  });
}
