// HR home «سلاسل مناديبك» card: «إضافة سلسلة», pending requests and the
// empty state (TAS-117). Fake data only.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';

Future<void> _pump(WidgetTester t, HrHomeChainsCard card) async {
  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(child: SizedBox(width: 352, child: card)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('header «إضافة سلسلة» opens the sheet callback', (t) async {
    var opened = 0;
    await _pump(
      t,
      HrHomeChainsCard(
        chains: const ['Fake Chain A', 'Fake Chain B'],
        selected: null,
        onSelected: (_) {},
        onAddChain: () => opened++,
      ),
    );
    expect(find.text('إضافة سلسلة'), findsOneWidget);
    await t.tap(find.byKey(HrHomeChainsCard.addChainKey));
    expect(opened, 1);
    expect(find.byKey(HrHomeChainsCard.pendingKey), findsNothing);
  });

  testWidgets('no callback: no add button, old empty text', (t) async {
    await _pump(
      t,
      HrHomeChainsCard(chains: const [], selected: null, onSelected: (_) {}),
    );
    expect(find.byKey(HrHomeChainsCard.addChainKey), findsNothing);
    expect(find.byKey(HrHomeChainsCard.addFirstChainKey), findsNothing);
    expect(find.text('لا توجد سلاسل مرتبطة بمناديبك بعد'), findsOneWidget);
  });

  testWidgets('empty: main action is «أضف أول سلسلة», no header button', (
    t,
  ) async {
    var opened = 0;
    await _pump(
      t,
      HrHomeChainsCard(
        chains: const [],
        selected: null,
        onSelected: (_) {},
        onAddChain: () => opened++,
      ),
    );
    expect(find.byKey(HrHomeChainsCard.addChainKey), findsNothing);
    await t.tap(find.byKey(HrHomeChainsCard.addFirstChainKey));
    expect(opened, 1);
  });

  testWidgets('pending: count, first 3 names, «+N», «عرض الكل»', (t) async {
    var openedAll = 0;
    await _pump(
      t,
      HrHomeChainsCard(
        chains: const ['Fake Chain A'],
        selected: null,
        onSelected: (_) {},
        onAddChain: () {},
        pendingRequests: const [
          'Fake Pending 1',
          'Fake Pending 2',
          'Fake Pending 3',
          'Fake Pending 4',
          'Fake Pending 5',
        ],
        onOpenRequests: () => openedAll++,
      ),
    );
    expect(find.text('طلبات قيد المراجعة (5)'), findsOneWidget);
    expect(find.text('Fake Pending 3'), findsOneWidget);
    expect(find.text('Fake Pending 4'), findsNothing);
    expect(find.text('+2 طلبات أخرى'), findsOneWidget);
    await t.tap(find.byKey(HrHomeChainsCard.pendingAllKey));
    expect(openedAll, 1);
  });
}
