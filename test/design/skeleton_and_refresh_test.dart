import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-387: the playground loading patterns as kit widgets (skeleton loader,
/// pull to refresh with a contained loading indicator).
void main() {
  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('Skeleton is a surfaceContainerHighest shape', (t) async {
    await t.pumpWidget(app(const Skeleton(width: 80, height: 14)));
    final box = t.widget<Container>(
      find.descendant(of: find.byType(Skeleton), matching: find.byType(Container)),
    );
    final cs = AppTheme.lightTheme().colorScheme;
    expect((box.decoration as BoxDecoration).color, cs.surfaceContainerHighest);
  });

  testWidgets('SkeletonSwitcher fades from skeleton to content', (t) async {
    Widget sw(bool loading) => app(
      SkeletonSwitcher(
        loading: loading,
        skeleton: const SummaryCardSkeleton(),
        child: const Text('المحتوى'),
      ),
    );
    await t.pumpWidget(sw(true));
    expect(find.byType(SummaryCardSkeleton), findsOneWidget);
    expect(find.text('المحتوى'), findsNothing);
    await t.pumpWidget(sw(false));
    await t.pumpAndSettle();
    expect(find.byType(SummaryCardSkeleton), findsNothing);
    expect(find.text('المحتوى'), findsOneWidget);
  });

  testWidgets('PullToRefresh shows a contained loading indicator', (t) async {
    var refreshed = 0;
    await t.pumpWidget(
      app(
        PullToRefresh(
          onRefresh: () async {
            refreshed++;
            await Future<void>.delayed(const Duration(seconds: 3));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [for (var i = 0; i < 20; i++) ListTile(title: Text('$i'))],
          ),
        ),
      ),
    );
    expect(find.byType(LoadingIndicator), findsNothing);
    await t.fling(find.text('0'), const Offset(0, 400), 1000);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(t.widget<LoadingIndicator>(find.byType(LoadingIndicator)).contained, isTrue);
    await t.pumpAndSettle();
    expect(refreshed, 1);
    expect(find.byType(LoadingIndicator), findsNothing);
  });
}
