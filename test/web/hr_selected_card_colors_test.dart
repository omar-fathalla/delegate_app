// TAS-185: every HR web stat card that works as a filter marks the selected
// card with primaryContainer / onPrimaryContainer. The status color stays on
// the icon and the number. Mobile keeps its own colors. Fake data only.
import 'dart:io';

import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_selected_card_colors.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

Delegate _supervisor() => Delegate(
  uid: 'fake-sup',
  firstName: 'مشرف',
  middleName: '',
  lastName: '',
  fullName: 'مشرف تجريبي',
  nationalityID: '',
  motherName: '',
  city: 'القاهرة',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'o-fake',
  organizationName: 'سلسلة تجريبية',
  companyUID: 'co-fake',
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: 'X1',
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

Future<ColorScheme> _pumpTab(WidgetTester t, {required bool web}) async {
  WebRuntimePolicy.debugIsWebOverride = web;
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final theme = AppTheme.lightTheme();
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar'),
      home: Scaffold(body: HRAttendanceTab(hrDelegate: _supervisor())),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return theme.colorScheme;
}

BoxDecoration _cardOf(WidgetTester t, String title) {
  final box = t.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(title).first,
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  tearDown(WebRuntimePolicy.debugReset);

  test('shared colors are the primary container tokens', () {
    final cs = AppTheme.lightTheme().colorScheme;
    final c = HrSelectedCardColors.of(cs);
    expect(c.background, cs.primaryContainer);
    expect(c.foreground, cs.onPrimaryContainer);
    expect(c.accent, cs.primary);
    expect(c.onAccent, cs.onPrimary);
  });

  group('attendance tab KPI cards', () {
    testWidgets('web: selected card is primaryContainer, not the status color', (
      t,
    ) async {
      final cs = await _pumpTab(t, web: true);

      expect(_cardOf(t, 'إجمالي').color, cs.primaryContainer);
      expect(_cardOf(t, 'لم يحضر').color, isNot(cs.primaryContainer));

      await t.tap(find.text('لم يحضر').first);
      await t.pump(const Duration(milliseconds: 400));
      final absent = _cardOf(t, 'لم يحضر');
      expect(absent.color, cs.primaryContainer);
      expect((absent.border! as Border).top.color, cs.primary);
      expect(_cardOf(t, 'إجمالي').color, isNot(cs.primaryContainer));

      final title = t.widget<Text>(find.text('لم يحضر').first);
      expect(title.style?.color, cs.onPrimaryContainer);
      expect(t.takeException(), isNull);
    });

    testWidgets('mobile keeps the status tint', (t) async {
      final cs = await _pumpTab(t, web: false);
      // «إجمالي» uses the primary color as its status color.
      expect(
        _cardOf(t, 'إجمالي').color,
        cs.primary.withValues(alpha: 0.14),
      );
    });
  });

  // TAS-353: the leaves filter is no longer a row of stat cards; TAS-387
  // (user review 27 Nov 2026) made it a connected ButtonGroup, so its
  // selected colour comes from the theme on web and mobile alike (TAS-185's
  // stat-card colours do not apply to it).
  test('leaves filter is a connected ButtonGroup', () {
    final source = File(
      'lib/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _buildFilterButtonGroup(');
    expect(start, isNonNegative);
    final body = source.substring(start, source.indexOf('Widget _buildRequestCard(', start));
    expect(body, contains('ButtonGroup<String>('));
    expect(body, contains('ButtonGroupVariant.connected'));
    expect(body, isNot(contains('HrSelectedCardColors')));
  });

  test('device unbind cards use the same shared colors', () {
    final source = File(
      'lib/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart',
    ).readAsStringSync();
    expect(source, contains('HrSelectedCardColors.of(colorScheme)'));
  });
}
