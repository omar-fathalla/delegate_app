import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_adaptive_sheet.dart';

/// TAS-137: one helper that opens a bottom sheet on mobile and a dialog or a
/// side sheet (from the reading end) on wide web windows.
void main() {
  tearDown(WebRuntimePolicy.debugReset);

  Future<void> pump(
    WidgetTester tester, {
    required bool web,
    Size size = const Size(1440, 900),
    HrSheetKind kind = HrSheetKind.dialog,
    TextDirection direction = TextDirection.rtl,
  }) async {
    WebRuntimePolicy.debugIsWebOverride = web;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHrAdaptiveSheet<void>(
                    context: context,
                    title: 'المظهر',
                    webKind: kind,
                    builder: (_) => const Text('المحتوى'),
                    actions: (ctx) => [
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('حفظ'),
                      ),
                    ],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('mobile opens a bottom sheet without a close button', (
    tester,
  ) async {
    await pump(tester, web: false);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('المظهر'), findsOneWidget);
    expect(find.text('المحتوى'), findsOneWidget);
    expect(find.byKey(const ValueKey('hr_sheet_close')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('narrow web window falls back to the bottom sheet', (
    tester,
  ) async {
    await pump(tester, web: true, size: const Size(420, 800));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('wide web opens a dialog with title, close and footer', (
    tester,
  ) async {
    await pump(tester, web: true);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('hr_sheet_close')), findsOneWidget);
    expect(find.byKey(const ValueKey('hr_sheet_actions')), findsOneWidget);
    final width = tester
        .getSize(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    expect(width, lessThanOrEqualTo(HrSheet.dialogWidth));

    await tester.tap(find.byKey(const ValueKey('hr_sheet_close')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('side sheet sits on the left edge in RTL, fixed width', (
    tester,
  ) async {
    await pump(tester, web: true, kind: HrSheetKind.side);
    final rect = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('hr_side_sheet')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(rect.left, 0);
    expect(rect.width, HrSheet.sideWidth);
    expect(rect.height, 900);
    expect(find.text('حفظ'), findsOneWidget);
  });

  testWidgets('side sheet sits on the right edge in LTR', (tester) async {
    await pump(
      tester,
      web: true,
      kind: HrSheetKind.side,
      direction: TextDirection.ltr,
    );
    final rect = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('hr_side_sheet')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(rect.right, 1440);
  });
}
