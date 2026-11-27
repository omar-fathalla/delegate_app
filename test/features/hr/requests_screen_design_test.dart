import 'dart:io';

import 'package:delegate_app/l10n/app_localizations_ar.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-387 («طلباتي», user review 27 Nov 2026). The screen reads Firestore
/// directly (FirebaseFirestore.instance), so the layout is guarded on the
/// source and the wording on the generated localizations.
void main() {
  final src = File(
    'lib/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart',
  ).readAsStringSync();

  test('request card is a SummaryCard opened with a container transform', () {
    expect(src, contains('SummaryCard('));
    expect(src, contains('OpenContainer<void>('));
    expect(src, contains('class _RequestDetailsPage'));
    expect(src, contains("ValueKey('request_menu_"));
    expect(src, contains('MenuAnchor('));
    expect(src, isNot(contains('⬅️')));
  });

  test('pending first, then the newest period', () {
    expect(src, contains("r['status'] == 'pending' ? 0 : 1"));
    expect(src, contains("r['startDate'] ?? r['createdAt']"));
  });

  test('connected ButtonGroup filter, pull to refresh, empty-state action', () {
    expect(src, contains("Key('requests_filter')"));
    expect(src, contains('ButtonGroupVariant.connected'));
    expect(src, isNot(contains('FilterChip(')));
    expect(src, contains('M3Refresh('));
    expect(src, isNot(contains('Symbols.refresh_rounded')));
    expect(src, contains("Key('requests_empty_new')"));
    expect(src, contains('DelayedLoadingIndicator()'));
    expect(src, contains('_planExpanded'));
  });

  test('tab badge counts pending requests', () {
    final main = File(
      'lib/features/home/presentation/pages/main_screen.dart',
    ).readAsStringSync();
    expect(main, contains('pendingRequestsCount(widget.delegate)'));
    expect(main, contains('badge: _pendingRequests > 0 ? _pendingRequests : null'));
    expect(src, contains("isEqualTo: 'pending'"));
  });

  test('durations read as Arabic words, never «1.0 ساعة»', () {
    final ar = AppLocalizationsAr();
    expect(ar.reqHoursWord(1), 'ساعة');
    expect(ar.reqHoursWord(2), 'ساعتين');
    expect(ar.reqHoursWord(3), 'ساعات');
    expect(ar.reqDaysWord(1), 'يوم');
    expect(ar.reqDaysWord(2), 'يومين');
    expect(ar.reqDaysWord(5), 'أيام');
    expect(ar.reqDaysWord(11), 'يوم');
  });
}
