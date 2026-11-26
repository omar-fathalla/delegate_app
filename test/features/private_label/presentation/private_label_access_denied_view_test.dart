import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_access_denied_view.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

void main() {
  testWidgets('PrivateLabelAccessDeniedView displays lock icon, title, and pop button in Arabic', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('ar'),
          Locale('en'),
        ],
        locale: Locale('ar'),
        home: PrivateLabelAccessDeniedView(
          title: 'Private Label Test',
          screenName: 'تقارير البرايفت ليبل',
        ),
      ),
    );

    expect(find.text('Private Label Test'), findsOneWidget);
    expect(find.text('صلاحية الوصول غير مفعلة'), findsOneWidget);
    expect(find.byIcon(Icons.lock_person_rounded), findsOneWidget);
    expect(find.textContaining('تقارير البرايفت ليبل'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('PrivateLabelAccessDeniedView displays English fallback when locale is en', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('ar'),
          Locale('en'),
        ],
        locale: Locale('en'),
        home: PrivateLabelAccessDeniedView(
          title: 'Private Label Test',
          screenName: 'Reports',
        ),
      ),
    );

    expect(find.text('Access Restricted'), findsOneWidget);
    expect(find.textContaining('Reports'), findsOneWidget);
    expect(find.text('Go Back'), findsOneWidget);
  });
}
