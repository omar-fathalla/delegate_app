import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/presentation/widgets/chain_multi_select.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

const _chains = [
  ChainOption(uid: 'o1', name: 'كارفور'),
  ChainOption(uid: 'o2', name: 'سبينيس'),
  ChainOption(uid: 'o3', name: 'هايبر وان'),
];

Widget _host({
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
  Set<String> duplicates = const {},
}) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ChainMultiSelect(
        chains: _chains,
        selectedUids: selected,
        onChanged: onChanged,
        duplicateUids: duplicates,
      ),
    ),
  );
}

void main() {
  testWidgets('اختيار الكل selects every chain', (tester) async {
    var selected = <String>{};
    await tester.pumpWidget(_host(
      selected: selected,
      onChanged: (next) => selected = next,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ChainMultiSelect.selectAllKey));
    await tester.pump();
    expect(selected, {'o1', 'o2', 'o3'});
  });

  testWidgets('deselect one chain after select-all leaves the others selected', (tester) async {
    var selected = {'o1', 'o2', 'o3'};
    await tester.pumpWidget(_host(
      selected: selected,
      onChanged: (next) => selected = next,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ChainMultiSelect.optionKey('o2')));
    await tester.pump();
    expect(selected, {'o1', 'o3'});
    // Select-all is no longer checked: tapping it again selects the missing one.
    await tester.pumpWidget(_host(
      selected: selected,
      onChanged: (next) => selected = next,
    ));
    await tester.pumpAndSettle();
    final allTile = tester.widget<CheckboxListTile>(find.byKey(ChainMultiSelect.selectAllKey));
    expect(allTile.value, isFalse);
  });

  testWidgets('duplicate skip shows a warning and keeps the remaining chain', (tester) async {
    var selected = {'o1', 'o2', 'o3'};
    await tester.pumpWidget(_host(
      selected: selected,
      onChanged: (next) => selected = next,
      duplicates: {'o1', 'o2'},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(ChainMultiSelect.warningKey), findsOneWidget);
    expect(
      find.text('المندوب مسجل بالفعل في: كارفور، سبينيس. سيتم تسجيله في: هايبر وان.'),
      findsOneWidget,
    );
  });
}
