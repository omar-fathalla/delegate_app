// Web-only list-detail layouts (delegates + requests) with fake data.
import 'dart:io';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_list_detail_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'web_golden.dart';

Delegate _d(String uid, String name) => Delegate(
      uid: uid, firstName: name, middleName: '', lastName: '',
      fullName: name, nationalityID: '', motherName: '', city: 'Cairo',
      phoneNumber: '0100000000$uid', gender: DelegateGender.male,
      position: DelegatePosition.supervisor, birthDate: DateTime(1990),
      organizationUID: 'org', organizationName: 'energizer', companyUID: 'c',
      companyName: 'energizer', status: DelegateStatus.active,
      delegatePublicId: 'X$uid', allReceiptCodes: const [], createdAt: DateTime(2024),
      createdBy: 't', hasPendingUpdate: false, isDeductedFromCompany: false,
      isPrinted: false, isProfileComplete: true, numberOfDocuments: 0,
      paymentAmount: 0, version: 1, documents: const [], role: UserRole.delegate,
    );

final _sup = _d('sup', 'مشرف تجريبي');
final _people = [_d('1', 'أحمد علي'), _d('2', 'محمد حسن'), _d('3', 'سارة محمود')];

/// Fake list that behaves like the shared tile: uses the selection scope.
class _FakeDelegatesList extends StatelessWidget {
  const _FakeDelegatesList();
  @override
  Widget build(BuildContext context) {
    final scope = AdminDelegateSelectionScope.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final p in _people)
        Material(
          key: ValueKey('tile_${p.uid}'),
          color: scope?.selectedUid == p.uid ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            title: Text(p.fullName, style: TextStyle(color: cs.onSurface)),
            onTap: () => scope?.onSelect(p),
          ),
        ),
    ]);
  }
}

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

Future<void> _pump(WidgetTester t, Size size, ThemeData theme, Widget home) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Cairo')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ar'),
    home: Scaffold(body: home),
  ));
  await t.pumpAndSettle();
}

Widget _delegates() => AdminDelegatesListDetailWeb(
      adminDelegate: _sup,
      listOverride: const _FakeDelegatesList(),
      detailBuilderOverride: (d) => Builder(builder: (c) => Center(
            child: Text('تفاصيل ${d.fullName}',
                style: TextStyle(color: Theme.of(c).colorScheme.onSurface, fontSize: 22)),
          )),
    );

int approved = 0, rejected = 0;

Widget _requests() => HRRequestsListDetailWeb(
      hrDelegate: _sup,
      listBuilderOverride: (onSelect, selectedKey) => Builder(builder: (c) {
        final cs = Theme.of(c).colorScheme;
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final p in _people)
            Material(
              color: selectedKey == 'k${p.uid}' ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                title: Text('طلب إجازة - ${p.fullName}', style: TextStyle(color: cs.onSurface)),
                onTap: () => onSelect(HRLeaveSelection(
                  key: 'k${p.uid}',
                  delegateName: p.fullName,
                  isPending: true,
                  approve: () async => approved++,
                  reject: () async => rejected++,
                  buildDetail: (ctx) => Text('إجازة اعتيادية · 2 يوم',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
                )),
              ),
            ),
        ]);
      }),
    );

void main() {
  setUpAll(_fonts);
  tearDown(() {
    final b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first.resetPhysicalSize();
    b.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  test('list pane width clamps 360..520', () {
    expect(listPaneWidthFor(600), kListPaneWidth);
    expect(listPaneWidthFor(900), closeTo(432, 0.01));
    expect(listPaneWidthFor(2000), kListPaneMaxWidth);
  });

  testWidgets('no scope => mobile path (maybeOf is null)', (t) async {
    AdminDelegateSelectionScope? s;
    await t.pumpWidget(Builder(builder: (c) {
      s = AdminDelegateSelectionScope.maybeOf(c);
      return const SizedBox();
    }));
    expect(s, isNull);
  });

  testWidgets('delegates 1280 light: empty state, then select', (t) async {
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme(), _delegates());
    expect(find.text('اختار مندوب لعرض التفاصيل'), findsOneWidget);
    final list = t.getSize(find.byKey(const ValueKey('list_detail_list_pane')));
    expect(list.width, greaterThanOrEqualTo(kListPaneWidth));
    expect(list.width, listPaneWidthFor(1280 - 32));
    await t.tap(find.text('محمد حسن'));
    await t.pumpAndSettle();
    expect(find.text('تفاصيل محمد حسن'), findsOneWidget);
    final tile = t.widget<Material>(find.byKey(const ValueKey('tile_2')));
    expect(tile.color, AppTheme.lightTheme().colorScheme.secondaryContainer);
    await expectWebGolden(find.byType(AdminDelegatesListDetailWeb), 'goldens/delegates_desktop_1280_light.png');
  });

  testWidgets('delegates 1600 dark', (t) async {
    await _pump(t, const Size(1600, 900), AppTheme.darkTheme(), _delegates());
    await t.tap(find.text('أحمد علي'));
    await t.pumpAndSettle();
    await expectWebGolden(find.byType(AdminDelegatesListDetailWeb), 'goldens/delegates_desktop_1600_dark.png');
  });

  testWidgets('requests 1280 light: approve/reject in header', (t) async {
    approved = rejected = 0;
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme(), _requests());
    expect(find.text('اختار طلب لعرض التفاصيل'), findsOneWidget);
    await t.tap(find.text('طلب إجازة - سارة محمود'));
    await t.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    await expectWebGolden(find.byType(HRRequestsListDetailWeb), 'goldens/requests_desktop_1280_light.png');
    await t.tap(find.text('اعتماد الإجازة'));
    await t.pumpAndSettle();
    expect(approved, 1);
    expect(find.text('اختار طلب لعرض التفاصيل'), findsOneWidget);
    await t.tap(find.text('طلب إجازة - أحمد علي'));
    await t.pumpAndSettle();
    await t.tap(find.text('رفض'));
    await t.pumpAndSettle();
    expect(rejected, 1);
  });

  testWidgets('requests 1600 dark', (t) async {
    await _pump(t, const Size(1600, 900), AppTheme.darkTheme(), _requests());
    await t.tap(find.text('طلب إجازة - محمد حسن'));
    await t.pumpAndSettle();
    await expectWebGolden(find.byType(HRRequestsListDetailWeb), 'goldens/requests_desktop_1600_dark.png');
  });
}
