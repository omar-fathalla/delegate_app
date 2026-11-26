import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

void main() {
  testWidgets('AdminHeader should render title and actions correctly', (WidgetTester tester) async {
    const String testTitle = 'Test Title';
    const String testSubtitle = 'Test Subtitle';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AdminHeader(
            title: testTitle,
            subtitle: testSubtitle,
            actions: [
              IconButton(
                key: const Key('test_action_button'),
                icon: const Icon(Icons.notifications),
                onPressed: () {},
              ),
            ],
            menuItems: const [
              PopupMenuItem(value: 'test', child: Text('Test Item')),
            ],
          ),
        ),
      ),
    );

    // Verify title and subtitle
    expect(find.text(testTitle), findsOneWidget);
    expect(find.text(testSubtitle), findsOneWidget);

    // Verify actions are passed and rendered
    expect(find.byKey(const Key('test_action_button')), findsOneWidget);

    // Verify menu items button is rendered
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });
}
