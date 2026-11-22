import 'package:delegate_app/features/admin/presentation/utils/anti_fraud_audit_display.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-79: the audit screen resolves names for display only; these helpers
/// are pure (no Firestore), so viewing the screen can no longer rewrite logs.
void main() {
  final branches = <Map<String, dynamic>>[
    {'id': 'b1', 'name': 'المعادي', 'latitude': 29.96, 'longitude': 31.25},
    {'id': 'b2', 'name': 'مدينة نصر', 'latitude': 30.05, 'longitude': 31.34},
  ];
  double flat(double a, double b, double c, double d) =>
      (a - c).abs() + (b - d).abs();

  group('resolveAuditBranchName', () {
    test('keeps a stored branch name', () {
      expect(resolveAuditBranchName({'branchName': 'الزمالك'}, branches), 'الزمالك');
    });

    test('uses branchUID when the stored name is the unknown placeholder', () {
      expect(
        resolveAuditBranchName({'branchName': kUnknownAuditBranch, 'branchUID': 'b2'}, branches),
        'مدينة نصر',
      );
    });

    test('falls back to the closest branch by coordinates', () {
      expect(
        resolveAuditBranchName(
          {'latitude': 30.04, 'longitude': 31.33},
          branches,
          distance: flat,
        ),
        'مدينة نصر',
      );
    });

    test('unknown when nothing matches', () {
      expect(resolveAuditBranchName({}, branches), kUnknownAuditBranch);
      expect(resolveAuditBranchName({'latitude': 1.0, 'longitude': 1.0}, const []), kUnknownAuditBranch);
    });

    test('does not mutate the log item (no write-back markers)', () {
      final item = <String, dynamic>{'docId': 'log1', 'latitude': 29.96, 'longitude': 31.25};
      final before = Map<String, dynamic>.from(item);
      resolveAuditBranchName(item, branches, distance: flat);
      expect(item, before);
    });
  });

  group('resolveAuditCompanyName', () {
    test('prefers the official name by companyUID', () {
      expect(
        resolveAuditCompanyName({'companyUID': 'c1', 'companyName': 'old'}, {'c1': 'شركة تسهيل'}),
        'شركة تسهيل',
      );
    });

    test('falls back to the stored name', () {
      expect(resolveAuditCompanyName({'companyUID': 'cX', 'companyName': 'old'}, {'c1': 'x'}), 'old');
      expect(resolveAuditCompanyName({}, {}), '');
    });
  });
}
