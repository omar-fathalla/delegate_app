import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:delegate_app/features/feedback/presentation/pages/my_feedbacks_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

/// TAS-387: «ملاحظاتي» from the playground: filter ButtonGroup, SummaryCards,
/// details with the admin's answer, skeletons, EmptyState. Fake data only.
class _MockBloc extends MockBloc<FeedbackEvent, FeedbackState>
    implements FeedbackBloc {}

class _FakeEvent extends Fake implements FeedbackEvent {}

Delegate _user({UserRole role = UserRole.delegate, DelegatePosition position = DelegatePosition.promoter}) => Delegate(
  uid: 'seed-fake-u',
  firstName: 'مستخدم',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مستخدم تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: position,
  birthDate: DateTime(1995),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
  // Empty: the header's company-code lookup skips Firestore in tests.
  companyUID: '',
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
  role: role,
);

FeedbackEntity _fb(String id, FeedbackStatus s, {String? answer}) =>
    FeedbackEntity(
      id: id,
      userId: 'seed-fake-u',
      userName: 'مستخدم تجريبي',
      userEmail: '',
      type: FeedbackType.bugReport,
      content: 'ملاحظة تجريبية $id',
      status: s,
      createdAt: DateTime(2026, 11, 20, 10),
      adminResponse: answer,
    );

void main() {
  setUpAll(() => registerFallbackValue(_FakeEvent()));

  Future<AppLocalizations> pump(WidgetTester t, FeedbackState s) async {
    final bloc = _MockBloc();
    whenListen(bloc, const Stream<FeedbackState>.empty(), initialState: s);
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: BlocProvider<FeedbackBloc>.value(
          value: bloc,
          child: MyFeedbacksScreen(delegate: _user()),
        ),
      ),
    );
    await t.pump();
    return lookupAppLocalizations(const Locale('ar'));
  }

  testWidgets('loading: skeletons', (t) async {
    await pump(t, FeedbackLoading());
    expect(find.byType(SummaryCardSkeleton), findsWidgets);
  });

  testWidgets('filter: open hides the resolved one', (t) async {
    await pump(
      t,
      FeedbacksLoaded(
        feedbacks: [
          _fb('a', FeedbackStatus.pending),
          _fb('b', FeedbackStatus.resolved, answer: 'رد تجريبي'),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('feedback_card_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_card_b')), findsOneWidget);
    await t.tap(find.textContaining('مفتوحة'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback_card_b')), findsNothing);
  });

  testWidgets('details show the admin answer', (t) async {
    await pump(
      t,
      FeedbacksLoaded(
        feedbacks: [_fb('b', FeedbackStatus.resolved, answer: 'رد تجريبي')],
      ),
    );
    await t.tap(find.byKey(const ValueKey('feedback_card_b')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feedback_details')), findsOneWidget);
    expect(find.text('رد تجريبي'), findsOneWidget);
  });

  testWidgets('empty: EmptyState with a send action', (t) async {
    final l10n = await pump(t, const FeedbacksLoaded(feedbacks: []));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text(l10n.sendFeedback), findsWidgets);
  });
}
