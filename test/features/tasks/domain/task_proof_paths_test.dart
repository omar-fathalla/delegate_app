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
}
