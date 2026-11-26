import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

/// Documents Arabic-default chrome. Screenshots for review are produced with
/// `--update-goldens` into `test/goldens/arabic/` when needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arabic default chrome shows RTL role/nav labels', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('ar'));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.roleBranchMarketing)),
            body: Text(l10n.login),
            bottomNavigationBar: NavigationBar(
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.store_rounded),
                  label: l10n.branches,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('تسويق الفروع'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الفروع'), findsOneWidget);
    expect(find.text('Branch Marketing'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Branches'), findsNothing);
  });
}
