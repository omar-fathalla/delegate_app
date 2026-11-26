import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: brightness,
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  const cols = [
    HrTableColumn('الاسم', 3),
    HrTableColumn('الحالة', 2, center: true),
  ];

  testWidgets('header is 56px and keys each title (TAS-115)', (tester) async {
    await tester.pumpWidget(
      _wrap(const HrTableHeader(columns: cols, keyPrefix: 'h_')),
    );
    expect(tester.getSize(find.byType(HrTableHeader)).height, 56);
    expect(find.byKey(const Key('h_الاسم')), findsOneWidget);
    expect(find.byKey(const Key('h_الحالة')), findsOneWidget);
  });

  testWidgets('rows are at least 64px', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const HrTableRow(
          columns: cols,
          cells: [Text('أحمد'), Text('نشط')],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(HrTableRow)).height,
      greaterThanOrEqualTo(64),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('status chips show an icon and a label ($brightness)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              HrStatusChip(label: 'نشط', tone: HrStatusTone.success),
              HrStatusChip(label: 'قيد المراجعة', tone: HrStatusTone.warning),
              HrStatusChip(label: 'مرفوض', tone: HrStatusTone.danger),
              HrStatusChip(label: 'إجازة', tone: HrStatusTone.info),
              HrStatusChip(label: 'متوقف', tone: HrStatusTone.neutral),
            ],
          ),
          brightness: brightness,
        ),
      );
      expect(find.byType(Icon), findsNWidgets(5));
      for (final label in ['نشط', 'قيد المراجعة', 'مرفوض', 'إجازة', 'متوقف']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  }

  testWidgets('table card scrolls sideways below its min width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        HrTableCard(
          minWidth: 860,
          builder: (context, width) =>
              SizedBox(height: 100, child: Text('$width')),
        ),
      ),
    );
    expect(find.text('860.0'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
