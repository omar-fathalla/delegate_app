// TAS-165: HR web messages use simple formal Arabic (owner decision). This
// guard greps the HR web sources for common colloquial Egyptian markers inside
// string literals, so a new empty state or snackbar does not bring them back.
// Comments and log lines are skipped. Intentional exceptions go in
// [_allowlist] as `path|literal`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories whose every Dart file is shown inside the HR web shell.
const _dirs = ['lib/features/hr/presentation', 'lib/web/hr_system'];

/// Screens hosted by the HR shell (see `hr_shell_tab.dart`) that live in
/// other features.
const _hostedFiles = [
  'lib/features/admin/presentation/pages/anti_fraud_audit_screen.dart',
  'lib/features/admin/presentation/pages/delegate_subscription_requests_page.dart',
  'lib/features/admin/presentation/pages/subscription_renewal_screen.dart',
  'lib/features/penalties/presentation/pages/admin_penalties_list_page.dart',
  'lib/features/penalties/presentation/pages/penalty_rules_catalog_page.dart',
  'lib/features/tasks/presentation/pages/admin_tasks_screen.dart',
  'lib/features/tracking/presentation/pages/delegate_tracking_screen.dart',
  'lib/features/tracking/presentation/widgets/live_tracking_load_error.dart',
  'lib/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart',
];

/// Colloquial words that have a plain formal equivalent.
const _markers = [
  'مفيش',
  'مافيش',
  'دلوقتي',
  'عشان',
  'علشان',
  'إيه',
  'مش',
  'بتاع',
  'بتاعة',
  'هيتم',
  'اتعمل',
  'اتحفظ',
  'لسه',
  'كده',
  'عاوز',
  'عايز',
  'النهاردة',
  'النهارده',
  'امبارح',
  'محدش',
  'مقدرناش',
  'نتايج',
  'غايبين',
];

/// `path|literal` pairs that are allowed on purpose.
const _allowlist = <String>{};

const _arabic = r'؀-ۿ';

void main() {
  test('HR web string literals use formal Arabic (TAS-165)', () {
    final files = <File>[
      for (final dir in _dirs)
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      for (final path in _hostedFiles) File(path),
    ];
    expect(files.length, greaterThan(_hostedFiles.length));

    final literal = RegExp(
      r"'(?:[^'\\\n]|\\.)*'" '|' r'"(?:[^"\\\n]|\\.)*"',
    );
    final markers = {
      for (final m in _markers)
        m: RegExp('(?<![$_arabic])${RegExp.escape(m)}(?![$_arabic])'),
    };

    final hits = <String>[];
    for (final file in files) {
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') ||
            line.contains('debugPrint') ||
            line.contains('developer.log')) {
          continue;
        }
        for (final match in literal.allMatches(line)) {
          final text = match.group(0)!;
          if (_allowlist.contains('$path|$text')) continue;
          final found = [
            for (final entry in markers.entries)
              if (entry.value.hasMatch(text)) entry.key,
          ];
          if (found.isNotEmpty) {
            hits.add('$path:${i + 1} [${found.join(', ')}] $text');
          }
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Use simple formal Arabic in HR web messages, e.g. «لا توجد …» '
          'instead of «مفيش …», or add the literal to _allowlist:\n'
          '${hits.join('\n')}',
    );
  });

  test('the guard catches a colloquial literal', () {
    final marker = RegExp('(?<![$_arabic])مفيش(?![$_arabic])');
    expect(marker.hasMatch("'مفيش إشعارات'"), isTrue);
    expect(marker.hasMatch("'لا توجد إشعارات'"), isFalse);
  });
}
