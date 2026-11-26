import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-353 (C-04): the create FAB shrinks to an icon while the list
/// scrolls down and comes back on scroll up; a sideways scroll (filter
/// chips) never touches it.
class _Screen extends StatefulWidget {
  const _Screen();
  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> with ExtendedFabScroll {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: M3ExtendedFab(
        key: const Key('fab'),
        icon: Icons.add,
        label: 'طلب جديد',
        onPressed: () {},
        extended: fabExtended,
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: onFabScroll,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                key: const Key('chips'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(width: 80, child: Text('chip $i')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const Key('list'),
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  bool extended(WidgetTester t) =>
      t.widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .isExtended;

  testWidgets('shrinks on scroll down, comes back on scroll up', (t) async {
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme(), home: const _Screen()),
    );
    expect(extended(t), isTrue);
    expect(find.text('طلب جديد'), findsOneWidget);

    await t.drag(find.byKey(const Key('list')), const Offset(0, -300));
    await t.pump();
    expect(extended(t), isFalse);

    await t.drag(find.byKey(const Key('list')), const Offset(0, 200));
    await t.pump();
    expect(extended(t), isTrue);
    await t.pumpAndSettle();
  });

  testWidgets('a sideways scroll leaves it extended', (t) async {
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme(), home: const _Screen()),
    );
    await t.drag(find.byKey(const Key('chips')), const Offset(-300, 0));
    await t.pump();
    expect(extended(t), isTrue);
    await t.pumpAndSettle();
  });

  testWidgets('the label is also its tooltip', (t) async {
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme(), home: const _Screen()),
    );
    expect(
      t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).tooltip,
      'طلب جديد',
    );
  });
}
