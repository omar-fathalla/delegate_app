import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrivateLabelReviewState - Filtering & Grouping', () {
    final audit1 = PrivateLabelAudit(
      id: 'a1',
      organizationUID: 'org1',
      companyUID: 'comp1',
      delegateUid: 'u1',
      delegateName: 'Ahmed',
      branchName: 'Abo Yousif',
      productName: 'Milk',
      referencePrice: 20.0,
      shelfPrice: 20.0,
      stockStatus: PrivateLabelStockStatus.available,
      productPhotoUrl: 'url1',
      pricePhotoUrl: 'url2',
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: DateTime(2026, 10, 7, 10, 0),
    );

    final audit2 = PrivateLabelAudit(
      id: 'a2',
      organizationUID: 'org1',
      companyUID: 'comp1',
      delegateUid: 'u2',
      delegateName: 'Mohamed',
      branchName: 'Semouha',
      productName: 'Cheese',
      referencePrice: 50.0,
      shelfPrice: 50.0,
      stockStatus: PrivateLabelStockStatus.available,
      productPhotoUrl: 'url3',
      pricePhotoUrl: 'url4',
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: DateTime(2026, 10, 7, 11, 0),
    );

    test('groupedByBranch groups audits by branch name alphabetically', () {
      final state = PrivateLabelReviewState(
        date: '2026-10-07',
        audits: [audit2, audit1],
      );

      final groups = state.groupedByBranch;
      expect(groups.keys.toList(), ['Abo Yousif', 'Semouha']);
      expect(groups['Abo Yousif']!.length, 1);
      expect(groups['Semouha']!.length, 1);
    });

    test('filters by selectedBranch correctly', () {
      final state = PrivateLabelReviewState(
        date: '2026-10-07',
        audits: [audit1, audit2],
        selectedBranch: 'Abo Yousif',
      );

      expect(state.filteredAudits.length, 1);
      expect(state.filteredAudits.first.branchName, 'Abo Yousif');
    });

    test('allAvailableBranches aggregates configured and audit branches', () {
      final state = PrivateLabelReviewState(
        date: '2026-10-07',
        audits: [audit1, audit2],
        branches: const ['Glim', 'Semouha'],
      );

      expect(state.allAvailableBranches, ['Abo Yousif', 'Glim', 'Semouha']);
    });
  });
}
