import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// TAS-158: the change-password sheet opens as a dialog on wide web windows
/// and stays a bottom sheet on mobile. Submit is never reached with valid
/// input, so Firebase Auth is not touched.
void main() {
  tearDown(WebRuntimePolicy.debugReset);

  Future<void> open(WidgetTester tester, {required bool web}) async {
    WebRuntimePolicy.debugIsWebOverride = web;
    // The mobile header row overflows a phone width with the test font
    // (Ahem), so the mobile case uses a wider view; the platform, not the
    // width, picks the bottom sheet there.
    tester.view.physicalSize =
        web ? const Size(1440, 900) : const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showUserChangePasswordSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('wide web opens a dialog with the buttons in its footer', (
    tester,
  ) async {
    await open(tester, web: true);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hr_sheet_actions')),
        matching: find.byKey(const ValueKey('change_password_submit')),
      ),
      findsOneWidget,
    );

    // Validation still runs from the footer button.
    await tester.tap(find.byKey(const ValueKey('change_password_submit')));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.enterCurrentPassword), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('change_password_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('mobile still opens the bottom sheet', (tester) async {
    await open(tester, web: false);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byKey(const ValueKey('hr_sheet_actions')), findsNothing);
  });
}
