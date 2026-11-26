import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_top_bar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart' show localeProvider;
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hr = Delegate(
  uid: 'seed-fake-hr',
  firstName: 'مشرف',
  middleName: '',
  lastName: 'تجريبي طويل الاسم',
  fullName: 'مشرف تجريبي طويل الاسم للتأكد من القص',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  paymentAmount: 0,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
  companyUID: 'seed-fake-co',
  companyName: 'شركة تجريبية باسم طويل جداً للتأكد من عدم تجاوز العرض',
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
  role: UserRole.hr,
);

/// TAS-103: the HR web top bar never overflows between a narrow browser
/// window and a wide desktop (the 800px window overflowed by 36px).
void main() {
  late ThemeCubit themeCubit;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
    localeProvider = LocaleProvider(await SharedPreferences.getInstance());
  });

  setUp(() async {
    themeCubit = ThemeCubit(await SharedPreferences.getInstance());
    WebRuntimePolicy.debugIsWebOverride = true;
  });

  tearDown(() => WebRuntimePolicy.debugIsWebOverride = null);

  for (final width in [600.0, 700.0, 768.0, 800.0, 840.0, 900.0, 1000.0, 1024.0, 1280.0, 1440.0]) {
    testWidgets('no overflow at ${width.toInt()}px', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        BlocProvider<ThemeCubit>.value(
          value: themeCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme(const Color(0xFF6750A4)),
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Row(
                children: [
                  // The real shell's sidebar: a rail below 1200px.
                  HRDesktopSidebar(
                    delegate: _hr,
                    selectedIndex: kHrTabDelegates,
                    isExpanded: width >= 1200,
                    onToggleExpanded: () {},
                    onItemSelected: (_) {},
                    onOpenSettings: () {},
                    onOpenProfile: () {},
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        HRDesktopTopBar(
                          delegate: _hr,
                          activeIndex: 0,
                          onRefresh: () {},
                          onMenuSelected: (_) {},
                          menuItems: const [],
                          webBell: HrWebHeaderBell(unread: 3, onPressed: () {}),
                          webAccount: (showName) =>
                              HrWebAccountButton(delegate: _hr, showName: showName),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      expect(find.byType(HRDesktopTopBar), findsOneWidget);
    });
  }
}
