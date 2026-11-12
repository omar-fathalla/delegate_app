import 'package:delegate_app/features/tasks/domain/task_proof_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('caps at 3, drops blanks, foreign roots, and duplicates', () {
    final paths = resolveTaskProofPaths([
      'task_proof/c1/del1/proof_del1_a.jpg',
      'task_proof/c1/del1/proof_del1_a.jpg',
      '',
      'task_images/c1/del1/task_del1_a.jpg',
      'task_proof/c1/del1/proof_del1_b.jpg',
      'task_proof/c1/del1/proof_del1_c.jpg',
      'task_proof/c1/del1/proof_del1_d.jpg',
    ]);
    expect(paths, [
      'task_proof/c1/del1/proof_del1_a.jpg',
      'task_proof/c1/del1/proof_del1_b.jpg',
      'task_proof/c1/del1/proof_del1_c.jpg',
    ]);
  });

  test('N1-r proof path includes the uploader uid twice', () {
    expect(
      taskProofPath(companyId: 'c1', uploaderUid: 'del1', token: '171'),
      'task_proof/c1/del1/proof_del1_171.jpg',
    );
    expect(
      taskProofFileName(
        uploaderUid: 'del1',
        token: '171',
      ).contains('proof_del1_2_'),
      isFalse,
    );
  });

  test('role helpers: company supervisors read all; other staff do not', () {
    expect(isCompanySupervisorRole('company-admin'), isTrue);
    expect(isCompanySupervisorRole('admin'), isTrue);
    expect(isCompanySupervisorRole('hr'), isFalse);
    expect(isCompanySupervisorRole('marketing'), isFalse);
    expect(isCompanySupervisorRole('superAdmin'), isFalse);
    expect(isTaskProofUploaderRole('delegate'), isTrue);
    expect(isTaskProofUploaderRole('branchesMarketingManager'), isTrue);
    expect(isTaskProofUploaderRole('marketing'), isTrue);
    expect(isTaskProofUploaderRole('hr'), isFalse);
    expect(isTaskProofUploaderRole('admin'), isFalse);
  });

  group('canWriteTaskProof (B1)', () {
    bool can({
      String? role = 'delegate',
      List<String?> ids = const ['del-1'],
      String? company = 'c1',
      String taskCompany = 'c1',
      String assignedTo = 'del-1',
      bool cancelled = false,
    }) => canWriteTaskProof(
      role: role,
      viewerIds: ids,
      viewerCompanyId: company,
      taskCompanyId: taskCompany,
      assignedTo: assignedTo,
      cancelled: cancelled,
    );

    test('assignee may attach; cancelled hides attach', () {
      expect(can(), isTrue);
      expect(can(cancelled: true), isFalse);
    });

    test('unassigned marketing, HR, accountant and other companies cannot', () {
      expect(can(role: 'marketingPromotion', ids: ['mp-1']), isFalse);
      expect(can(role: 'hr', ids: ['hr-1']), isFalse);
      expect(can(role: 'accountant', ids: ['del-1']), isFalse);
      expect(can(company: 'c2'), isFalse);
      expect(can(ids: ['del-2']), isFalse);
    });

    test('«الكل» shows attach only to same-company field delegates', () {
      expect(can(assignedTo: 'all', ids: ['del-2']), isTrue);
      expect(can(assignedTo: 'الكل', ids: ['del-2']), isTrue);
      expect(can(assignedTo: 'all', role: 'marketing'), isFalse);
      expect(can(assignedTo: 'all', role: 'branchesMarketingManager'), isFalse);
      expect(can(assignedTo: 'all', role: 'marketingPromotion'), isFalse);
      expect(can(assignedTo: 'all', company: 'c2'), isFalse);
    });

    test('sector tasks show attach only to the matching sector role', () {
      expect(
        can(
          assignedTo: 'all_branch_marketing',
          role: 'branchesMarketingManager',
        ),
        isTrue,
      );
      expect(
        can(assignedTo: 'all_branch_marketing', role: 'marketing'),
        isTrue,
      );
      expect(
        can(assignedTo: 'all_branch_marketing', role: 'marketingPromotion'),
        isFalse,
      );
      expect(can(assignedTo: 'all_branch_marketing'), isFalse);
      expect(
        can(assignedTo: 'all_marketing_promotion', role: 'marketingPromotion'),
        isTrue,
      );
      expect(
        can(assignedTo: 'all_marketing_promotion', role: 'marketing'),
        isFalse,
      );
    });
  });
}
