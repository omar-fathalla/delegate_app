import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:delegate_app/features/update/presentation/pages/update_required_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';

Widget _app({required Widget home, Locale locale = const Locale('ar')}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar'), Locale('en')],
    locale: locale,
    home: home,
  );
}

const _blocked = AppVersionGateDecision(
  updateRequired: true,
  currentVersion: '1.14.3',
  minVersion: '1.15.0',
  storeUrl: 'https://play.google.com/store/apps/details?id=com.tashil.delegate',
);

void main() {
  testWidgets('shows the title, both versions and opens the store url', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      _app(
        home: UpdateRequiredScreen(
          decision: _blocked,
          openUrl: (uri) async {
            opened = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('مطلوب تحديث التطبيق'), findsOneWidget);
    expect(find.textContaining('1.14.3'), findsOneWidget);
    expect(find.textContaining('1.15.0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_required_store_button')));
    await tester.pump();
    expect(opened.toString(), _blocked.storeUrl);
  });

  testWidgets('cannot be popped with the back button', (tester) async {
    // Push the page on top of another route so a pop would actually go
    // somewhere; PopScope(canPop: false) must keep it on screen.
    await tester.pumpWidget(_app(home: const Scaffold(body: Text('home'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            UpdateRequiredScreen(decision: _blocked, openUrl: (_) async => true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);

    // maybePop returns true when the pop was handled, even when PopScope
    // vetoes it, so assert on what is on screen instead.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('shows the manual hint instead of a button without a store url', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        home: UpdateRequiredScreen(
          decision: const AppVersionGateDecision(
            updateRequired: true,
            currentVersion: '1.0.0',
            minVersion: '1.1.0',
            storeUrl: '',
          ),
          openUrl: (_) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('update_required_store_button')), findsNothing);
    expect(find.textContaining('App Store'), findsOneWidget);
  });

  testWidgets('tells the user when the store could not be opened', (tester) async {
    await tester.pumpWidget(
      _app(home: UpdateRequiredScreen(decision: _blocked, openUrl: (_) async => false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('update_required_store_button')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
