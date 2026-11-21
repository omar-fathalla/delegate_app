import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';

/// TAS-136: inner pages open inside the shell's content area on web, with a
/// breadcrumb, a back button and a max width; without a host they keep the
/// old full-screen push.
void main() {
  Widget page(BuildContext context, bool inShell) => Scaffold(
    appBar: inShell ? null : AppBar(title: const Text('إنشاء مهمة')),
    body: Text(inShell ? 'in-shell' : 'full-screen'),
  );

  Widget opener() => Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () =>
            pushHrInnerPage<void>(context, title: 'إنشاء مهمة', builder: page),
        child: const Text('open'),
      ),
    ),
  );

  testWidgets('with a host: opens inside the nested navigator', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              const SizedBox(
                width: 260,
                child: Text('sidebar', key: ValueKey('sidebar')),
              ),
              Expanded(
                child: HrInnerPageHost(
                  navigatorKey: key,
                  parentTitle: 'المهام',
                  child: Navigator(
                    key: key,
                    pages: [
                      MaterialPage<void>(child: Scaffold(body: opener())),
                    ],
                    onDidRemovePage: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sidebar stays, page has the breadcrumb and no own app bar.
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(find.text('in-shell'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hr_inner_page_breadcrumb')),
        matching: find.text('المهام'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hr_inner_page_title')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('hr_inner_page_content'))).width,
      lessThanOrEqualTo(HrInnerPageWidth.form),
    );

    // Back returns to the tab.
    await tester.tap(find.byKey(const ValueKey('hr_inner_page_back')));
    await tester.pumpAndSettle();
    expect(find.text('in-shell'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('parent breadcrumb pops back to the tab', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: HrInnerPageHost(
          navigatorKey: key,
          parentTitle: 'المهام',
          child: Navigator(
            key: key,
            pages: [MaterialPage<void>(child: Scaffold(body: opener()))],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr_inner_page_parent')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('without a host: full-screen push with its own app bar', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: opener())));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('full-screen'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hr_inner_page_breadcrumb')),
      findsNothing,
    );
  });

  test('page label uses the short web name', () {
    expect(hrShellPageLabel(kHrTabPayroll, isWeb: true), 'الرواتب');
    expect(
      hrShellPageLabel(kHrTabPayroll, isWeb: false),
      'مسير الرواتب والعمولات',
    );
  });
}
