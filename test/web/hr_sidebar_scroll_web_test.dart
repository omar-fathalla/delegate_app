// Web HR sidebar: at common desktop windows the menu scrolls between the
// header and the pinned footer, so every tool can be reached without the
// profile row or الإعدادات covering it. Mobile keeps its original list.
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Delegate _delegate(UserRole role) => Delegate(
  uid: 'seed-fake-${role.name}',
  firstName: 'موظف',
  middleName: '',
  lastName: 'وهمي',
  fullName: 'موظف وهمي',
  nationalityID: '__firebase_auth__:fake@example.com',
  motherName: '',
  city: '',
  phoneNumber: '01000000006',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-hr-org',
  organizationName: 'Fake Test Organization',
  companyUID: 'seed-fake-co-alpha',
  companyName: 'Fake Company Alpha',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: role,
  email: 'fake@example.com',
);

final _scrollArea = find.byKey(const ValueKey('hr_sidebar_scroll'));
final _scrollable = find.descendant(
  of: _scrollArea,
  matching: find.byType(Scrollable),
);

class _Host extends StatefulWidget {
  final Delegate delegate;
  final int initialIndex;
  final bool expanded;

  const _Host({
    required this.delegate,
    required this.initialIndex,
    this.expanded = true,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int selected = widget.initialIndex;

  void select(int index) => setState(() => selected = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        textDirection: TextDirection.rtl,
        children: [
          HRDesktopSidebar(
            delegate: widget.delegate,
            selectedIndex: selected,
            onItemSelected: select,
            isExpanded: widget.expanded,
            onToggleExpanded: () {},
            onOpenSettings: () {},
            onOpenProfile: () {},
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Delegate delegate, {
  int initialIndex = kHrTabOverview,
  bool expanded = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Host(
        delegate: delegate,
        initialIndex: initialIndex,
        expanded: expanded,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Top edge of the pinned footer (the divider right under the menu).
double _footerTop(WidgetTester tester) => tester
    .getRect(
      find.descendant(
        of: find.byType(HRDesktopSidebar),
        matching: find.byType(Divider),
      ).last,
    )
    .top;

void main() {
  setUp(() async {
    sl.allowReassignment = true;
    SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
    WebRuntimePolicy.debugReset();
  });

  tearDown(WebRuntimePolicy.debugReset);

  group('web sidebar scrolls above the pinned footer', () {
    setUp(() => WebRuntimePolicy.debugIsWebOverride = true);

    for (final size in const [Size(1440, 900), Size(1280, 720), Size(1024, 768)]) {
      for (final role in [UserRole.hr, UserRole.admin]) {
        final label = '${size.width.toInt()}x${size.height.toInt()} ${role.name}';

        testWidgets('$label: every tool is reachable and nothing overlaps', (
          tester,
        ) async {
          final delegate = _delegate(role);
          await _pump(tester, size, delegate);

          final viewport = tester.getRect(_scrollArea);
          final footerTop = _footerTop(tester);
          expect(viewport.bottom, lessThanOrEqualTo(footerTop));
          final settings = tester.getRect(find.text('الإعدادات'));
          expect(settings.top, greaterThanOrEqualTo(footerTop));
          expect(settings.bottom, lessThanOrEqualTo(size.height));

          final items = hrShellItems(
            delegate: delegate,
            isWeb: true,
            placement: HrShellPlacement.sidebar,
          );
          // The list must actually need scrolling at these heights, or the
          // check below would pass without exercising the fix.
          final scrollState = tester.state<ScrollableState>(_scrollable);
          expect(scrollState.position.maxScrollExtent, greaterThan(0));

          for (final item in items) {
            // «الرئيسية» is also a section title above its row.
            final title = find
                .descendant(of: _scrollArea, matching: find.text(item.title))
                .last;
            await tester.scrollUntilVisible(title, 80, scrollable: _scrollable);
            await tester.pumpAndSettle();
            final rect = tester.getRect(title);
            expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: item.title);
            expect(rect.bottom, lessThanOrEqualTo(viewport.bottom), reason: item.title);
            expect(rect.bottom, lessThanOrEqualTo(footerTop), reason: item.title);

            if (item.tabIndex != null) {
              await tester.tap(title);
              await tester.pumpAndSettle();
              expect(
                tester.state<_HostState>(find.byType(_Host)).selected,
                item.tabIndex,
                reason: item.title,
              );
            }
          }
        });
      }
    }

    testWidgets('the last tools are reachable by wheel to the end', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _delegate(UserRole.hr));
      final scrollState = tester.state<ScrollableState>(_scrollable);
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(_scrollArea);
      final footerTop = _footerTop(tester);
      for (final title in const [
        'المهام',
        'أذونات التصوير',
        'لائحة الغرامات والجزاءات',
        'نظام الغرامات والمخالفات',
      ]) {
        final rect = tester.getRect(
          find.descendant(of: _scrollArea, matching: find.text(title)),
        );
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom), reason: title);
        expect(rect.bottom, lessThan(footerTop), reason: title);
      }
    });

    testWidgets('selecting an off-screen tool scrolls it into view', (
      tester,
    ) async {
      await _pump(tester, const Size(1280, 720), _delegate(UserRole.hr));
      final penalties = find.descendant(
        of: _scrollArea,
        matching: find.text('نظام الغرامات والمخالفات'),
      );
      final viewport = tester.getRect(_scrollArea);
      expect(tester.getRect(penalties).top, greaterThan(viewport.bottom));

      tester.state<_HostState>(find.byType(_Host)).select(kHrTabPenalties);
      await tester.pumpAndSettle();
      final rect = tester.getRect(penalties);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    });

    testWidgets('opening on a low tool starts with it visible', (tester) async {
      await _pump(
        tester,
        const Size(1024, 768),
        _delegate(UserRole.admin),
        initialIndex: kHrTabPenalties,
      );
      final viewport = tester.getRect(_scrollArea);
      final rect = tester.getRect(
        find.descendant(
          of: _scrollArea,
          matching: find.text('نظام الغرامات والمخالفات'),
        ),
      );
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    });

    testWidgets('scrollbar is always visible and physics do not bounce', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _delegate(UserRole.hr));
      final bar = tester.widget<Scrollbar>(
        find.ancestor(of: _scrollArea, matching: find.byType(Scrollbar)).first,
      );
      expect(bar.thumbVisibility, isTrue);
      final scroll = tester.widget<SingleChildScrollView>(_scrollArea);
      expect(scroll.physics, isA<ClampingScrollPhysics>());
    });

    testWidgets('collapsed rail also scrolls above the footer', (tester) async {
      await _pump(
        tester,
        const Size(1280, 720),
        _delegate(UserRole.hr),
        expanded: false,
      );
      final viewport = tester.getRect(_scrollArea);
      expect(viewport.bottom, lessThanOrEqualTo(_footerTop(tester)));
      final scrollState = tester.state<ScrollableState>(_scrollable);
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final gavel = tester.getRect(
        find.descendant(
          of: _scrollArea,
          matching: find.byIcon(Icons.gavel_outlined),
        ),
      );
      expect(gavel.bottom, lessThanOrEqualTo(viewport.bottom));
    });
  });

  group('mobile sidebar unchanged', () {
    setUp(() => WebRuntimePolicy.debugIsWebOverride = false);

    testWidgets('keeps the bouncing ListView and no web scroll area', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(1024, 768),
        _delegate(UserRole.hr),
        initialIndex: kHrTabAttendance,
      );
      expect(find.byType(HrSidebarScrollArea), findsNothing);
      final list = tester.widget<ListView>(
        find.descendant(
          of: find.byType(HRDesktopSidebar),
          matching: find.byType(ListView),
        ),
      );
      expect(list.physics, isA<BouncingScrollPhysics>());
      expect(list.padding, const EdgeInsets.symmetric(horizontal: 10, vertical: 12));
      for (final title in const [
        'الحضور والانصراف',
        'الخريطة الحية',
        'مناديب الشركة',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });
  });

  group('penalties tab scope', () {
    test('web HR opens only their own penalties', () {
      WebRuntimePolicy.debugIsWebOverride = true;
      final host = hrShellTab(
        index: kHrTabPenalties,
        delegate: _delegate(UserRole.hr),
        onNavigateToTab: (_) {},
      ) as HrPenaltiesHost;
      expect(host.ownPenaltiesOnly, isTrue);
    });

    test('web supervisors keep the company list', () {
      WebRuntimePolicy.debugIsWebOverride = true;
      final host = hrShellTab(
        index: kHrTabPenalties,
        delegate: _delegate(UserRole.admin),
        onNavigateToTab: (_) {},
      ) as HrPenaltiesHost;
      expect(host.ownPenaltiesOnly, isFalse);
    });

    test('mobile is untouched', () {
      WebRuntimePolicy.debugIsWebOverride = false;
      expect(
        HrPenaltiesHost(admin: _delegate(UserRole.hr)).ownPenaltiesOnly,
        isFalse,
      );
    });
  });
}
