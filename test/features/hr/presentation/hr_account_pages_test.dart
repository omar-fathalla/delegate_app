import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_user_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/submit_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/pages/submit_feedback_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

class _MockSubmit extends Mock implements SubmitFeedbackUseCase {}

class _MockGetFeedbacks extends Mock implements GetUserFeedbacksUseCase {}

final _hr = Delegate(
  uid: 'hr-1',
  firstName: 'Fake',
  middleName: '',
  lastName: 'HR',
  fullName: 'Fake HR',
  nationalityID: '0',
  motherName: '',
  city: 'Cairo',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1995),
  organizationUID: 'org-1',
  organizationName: 'Org',
  companyUID: 'co-1',
  companyName: 'Company',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'test',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.hr,
);

/// TAS-157: settings, profile and send feedback open as inner pages of the
/// wide web HR shell (720 wide, sidebar kept, no own app bar). Without a
/// shell host they keep the full-screen push.
void main() {
  setUpAll(() async {
    sl.allowReassignment = true;
    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
    }
    localeProvider = sl<LocaleProvider>();
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
    sl.registerFactory<FeedbackBloc>(
      () => FeedbackBloc(
        submitFeedbackUseCase: _MockSubmit(),
        getUserFeedbacksUseCase: _MockGetFeedbacks(),
      ),
    );
  });

  setUp(() => WebRuntimePolicy.debugIsWebOverride = true);

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrAccountPages.debugProfileBuilder = null;
    HrAccountPages.debugFeedbackBuilder = null;
  });

  void wideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => BlocProvider<ThemeCubit>.value(
    value: sl<ThemeCubit>(),
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar'),
      home: home,
    ),
  );

  /// A shell like [HRMainScreen] on wide web: a sidebar, a top bar above
  /// the host (where the account button lives) and the nested navigator.
  Widget shell({
    required GlobalKey<NavigatorState> navKey,
    required Widget Function(BuildContext inner) tab,
    Widget? topBar,
  }) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Row(
        children: [
          const SizedBox(
            width: 260,
            child: Text('sidebar', key: ValueKey('sidebar')),
          ),
          Expanded(
            child: Column(
              children: [
                SizedBox(height: 64, child: topBar ?? const SizedBox()),
                Expanded(
                  child: HrInnerPageHost(
                    navigatorKey: navKey,
                    parentTitle: 'الرئيسية',
                    child: Navigator(
                      key: navKey,
                      pages: [
                        MaterialPage<void>(
                          child: Scaffold(body: Builder(builder: tab)),
                        ),
                      ],
                      onDidRemovePage: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget opener(String label, void Function(BuildContext) onTap) => Builder(
    builder: (context) => Center(
      child: TextButton(onPressed: () => onTap(context), child: Text(label)),
    ),
  );

  void expectInnerPage(WidgetTester tester, String title) {
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hr_inner_page_breadcrumb')),
        matching: find.text(title),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('hr_inner_page_content'))).width,
      HrInnerPageWidth.form,
    );
  }

  testWidgets('settings open inside the shell, 720 wide, no app bar', (
    tester,
  ) async {
    wideWindow(tester);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      app(
        shell(
          navKey: navKey,
          tab: (_) =>
              opener('open', (c) => HrAccountPages.openSettings(c, _hr)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expectInnerPage(tester, HrAccountPages.settingsTitle);
    expect(
      find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(AppBar),
      ),
      findsNothing,
    );

    // Back returns to the tab, the shell stays.
    await tester.tap(find.byKey(const ValueKey('hr_inner_page_back')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('«إرسال ملاحظات» from settings opens as an inner page', (
    tester,
  ) async {
    wideWindow(tester);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      app(
        shell(
          navKey: navKey,
          tab: (_) =>
              opener('open', (c) => HrAccountPages.openSettings(c, _hr)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // TAS-387: the settings rows use Symbols icons.
    await tester.tap(find.byIcon(Symbols.rate_review_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SubmitFeedbackScreen), findsOneWidget);
    expectInnerPage(tester, HrAccountPages.feedbackTitle);
    expect(
      find.descendant(
        of: find.byType(SubmitFeedbackScreen),
        matching: find.byType(AppBar),
      ),
      findsNothing,
    );

    // Back goes to settings, still inside the shell.
    await tester.tap(find.byKey(const ValueKey('hr_inner_page_back')));
    await tester.pumpAndSettle();
    expect(find.byType(SubmitFeedbackScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
  });

  testWidgets('profile opens as an inner page', (tester) async {
    wideWindow(tester);
    bool? inShell;
    HrAccountPages.debugProfileBuilder = (_, shellPage) {
      inShell = shellPage;
      return const Scaffold(body: Text('profile-page'));
    };
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      app(
        shell(
          navKey: navKey,
          tab: (_) => opener('open', (c) => HrAccountPages.openProfile(c, _hr)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('profile-page'), findsOneWidget);
    expect(inShell, isTrue);
    expectInnerPage(tester, HrAccountPages.profileTitle);
  });

  testWidgets('account menu «الملف الشخصي» uses the shell handler', (
    tester,
  ) async {
    wideWindow(tester);
    final navKey = GlobalKey<NavigatorState>();
    HrAccountPages.debugProfileBuilder = (_, _) =>
        const Scaffold(body: Text('profile-page'));
    await tester.pumpWidget(
      app(
        shell(
          navKey: navKey,
          tab: (_) => const Text('tab'),
          // The top bar is above the host, like in HRMainScreen; the shell
          // routes the tap through its inner navigator.
          topBar: HrWebAccountButton(
            delegate: _hr,
            showName: true,
            onOpenProfile: () =>
                HrAccountPages.openProfile(navKey.currentContext!, _hr),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(HrWebAccountButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr_web_profile_open')));
    await tester.pumpAndSettle();

    expect(find.text('profile-page'), findsOneWidget);
    expectInnerPage(tester, HrAccountPages.profileTitle);
  });

  testWidgets('without a shell host settings keep the full-screen page', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: opener('open', (c) => HrAccountPages.openSettings(c, _hr)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(AppBar),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hr_inner_page_breadcrumb')),
      findsNothing,
    );
  });
}
