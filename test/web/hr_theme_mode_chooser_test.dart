import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';

/// TAS-174: the web account menu offers system / light / dark, replacing the
/// light/dark toggle the web top bar used to show.
void main() {
  testWidgets('selecting «داكن» sets dark mode, «تلقائي» sets system', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = ThemeCubit(await SharedPreferences.getInstance());
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const Center(child: HrThemeModeChooser()),
            ),
          ),
        ),
      ),
    );
    expect(find.text('المظهر'), findsOneWidget);
    for (final label in ['تلقائي', 'فاتح', 'داكن']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('داكن'));
    await tester.pumpAndSettle();
    expect(cubit.state.themeMode, ThemeMode.dark);

    await tester.tap(find.text('تلقائي'));
    await tester.pumpAndSettle();
    expect(cubit.state.themeMode, ThemeMode.system);
  });
}
