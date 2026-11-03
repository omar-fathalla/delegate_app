import 'dart:io';
// Tests + review screenshots for the WEB-ONLY admin desktop shell (fake data).
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_shell_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _sup = Delegate(
  uid: 'test_sup', firstName: 'مشرف', middleName: '', lastName: 'تجريبي',
  fullName: 'مشرف تجريبي', nationalityID: '', motherName: '', city: 'Cairo',
  phoneNumber: '', gender: DelegateGender.male,
  position: DelegatePosition.supervisor, birthDate: DateTime(1990),
  organizationUID: 'org', organizationName: 'Org', companyUID: 'c',
  companyName: 'energizer', status: DelegateStatus.active,
  delegatePublicId: 'X', allReceiptCodes: const [], createdAt: DateTime(2024),
  createdBy: 't', hasPendingUpdate: false, isDeductedFromCompany: false,
  isPrinted: false, isProfileComplete: true, numberOfDocuments: 0,
  paymentAmount: 0, version: 1, documents: const [], role: UserRole.admin,
);

Widget _fake(String t) => Builder(builder: (c) {
      final cs = Theme.of(c).colorScheme;
      return ListView(padding: const EdgeInsets.all(24), children: [
        Text('محتوى تجريبي: $t', style: TextStyle(color: cs.onSurface, fontSize: 20)),
        const SizedBox(height: 16),
        for (var i = 0; i < 4; i++)
          Card(color: cs.surfaceContainer, child: const SizedBox(height: 80)),
      ]);
    });

Future<void> _fonts() async {
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'));
  await cairo.load();
  final mi = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await mi.load();
  final sym = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'));
  await sym.load();
}

Future<void> _pump(WidgetTester t, Size size, ThemeData theme) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Cairo')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ar'),
    home: AdminDesktopShellWeb(
      delegate: _sup,
      screensOverride: [_fake('الرئيسية'), _fake('المناديب'), _fake('الحضور'), _fake('الطلبات')],
      pendingCountOverride: (c) => Stream.value(c == 'leave_requests' ? 3 : 1),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(_fonts);
  tearDown(() {
    final b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first.resetPhysicalSize();
    b.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('shouldUse is false off-web (mobile unchanged)', (t) async {
    late bool v;
    await t.pumpWidget(Builder(builder: (c) { v = AdminDesktopShellWeb.shouldUse(c, _sup); return const SizedBox(); }));
    expect(v, isFalse);
  });

  testWidgets('1280: drawer, 4 destinations, switches tabs', (t) async {
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme());
    expect(find.byType(NavigationDrawer), findsOneWidget);
    expect(find.text('الحضور'), findsWidgets);
    // Extra supervisor menu items + badges from the exposed sources.
    expect(find.text('المهام'), findsOneWidget);
    expect(find.text('أذونات التصوير'), findsOneWidget);
    expect(find.text('نظام الغرامات والمخالفات'), findsOneWidget);
    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    await expectLater(find.byType(AdminDesktopShellWeb), matchesGoldenFile('goldens/admin_desktop_1280_light.png'));
    await t.tap(find.text('الطلبات').first);
    await t.pumpAndSettle();
    expect(find.text('محتوى تجريبي: الطلبات'), findsOneWidget);
  });

  testWidgets('1000: navigation rail', (t) async {
    await _pump(t, const Size(1000, 800), AppTheme.lightTheme());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const ValueKey('rail_more')), findsOneWidget);
    await expectLater(find.byType(AdminDesktopShellWeb), matchesGoldenFile('goldens/admin_desktop_1000_rail.png'));
  });

  testWidgets('1600 dark', (t) async {
    await _pump(t, const Size(1600, 900), AppTheme.darkTheme());
    await expectLater(find.byType(AdminDesktopShellWeb), matchesGoldenFile('goldens/admin_desktop_1600_dark.png'));
  });
}
