import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/money.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-357: the rules catalog searches with the official SearchBar, shows
/// amounts with Money (thousands separator, two decimals) and never paints a
/// repeat fine in the error colour. No Firebase app here, so the page uses
/// its offline copy of the official schedule. Fake data only.
Delegate _delegate() => Delegate(
  uid: 'seed-fake-d',
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
  role: UserRole.delegate,
);

void main() {
  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: PenaltyRulesCatalogPage(currentDelegate: _delegate()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('search is the official SearchBar', (t) async {
    await pump(t);
    expect(find.byKey(const Key('penalty_rules_search')), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
  });

  testWidgets('amounts use Money and a repeat fine is not an error', (t) async {
    await pump(t);
    final first = officialViolationsSchedule.firstWhere(
      (v) => !v.isConfidential && v.repeatedFine != null && v.repeatedFine! > 0,
    );
    expect(find.text(Money.formatEgp(first.defaultFine)), findsWidgets);
    final repeat = find.text(Money.formatEgp(first.repeatedFine!));
    expect(repeat, findsWidgets);
    final error = AppTheme.lightTheme().colorScheme.error;
    for (final e in repeat.evaluate()) {
      expect((e.widget as Text).style?.color, isNot(error));
    }
  });
}
