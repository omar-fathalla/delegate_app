import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-387: the delegate tasks list follows the playground. Guarded on the
/// source (cards push go_router routes): SummaryCards with the due date and
/// the sender across the card, groups overdue / coming up / finished, one
/// connected ButtonGroup filter, the next step in a ⋮ menu, PullToRefresh,
/// skeletons and EmptyState.
void main() {
  final src = File(
    'lib/features/tasks/presentation/pages/delegate_tasks_screen.dart',
  ).readAsStringSync();

  test('cards, groups and filter', () {
    expect(src, contains('return SummaryCard('));
    expect(src, contains('SummaryFact('));
    expect(src, contains('l10n.tasksGroupOverdue'));
    expect(src, contains('l10n.tasksGroupOpen'));
    expect(src, contains('l10n.tasksGroupDone'));
    expect(src, contains("Key('tasks_filter')"));
    expect(src, contains('ButtonGroupVariant.connected'));
    expect(src, isNot(contains('FilterChip(')));
  });

  test('next step in a menu, no double purple circle', () {
    expect(src, contains('MenuAnchor('));
    expect(src, isNot(contains('IconButton.filled(')));
  });

  test('loading, refresh, empty', () {
    expect(src, contains('PullToRefresh('));
    expect(src, contains('SummaryCardSkeleton()'));
    expect(src, contains("Key('tasks_empty')"));
    expect(src, isNot(contains('Symbols.refresh_rounded),\n            // TAS-356')));
  });
}
