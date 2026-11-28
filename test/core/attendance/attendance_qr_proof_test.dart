import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-372: what the scanner sends to delegateCheckIn for each kind of QR.
void main() {
  test('signed QR sends its signed fields', () {
    final proof = attendanceQrProof({
      'type': 'attendance',
      'v': 2,
      'branch': 'Fake Alpha',
      'branchId': ' b1 ',
      'organizationUID': 'o1',
      'qrVersion': 3,
      'sig': 'abc_-',
    });
    expect(proof, {
      'v': 2,
      'branchId': 'b1',
      'organizationUID': 'o1',
      'qrVersion': 3,
      'sig': 'abc_-',
    });
  });

  test('old JSON QR, branch name only, or a broken signed QR is legacy', () {
    expect(
      attendanceQrProof({
        'type': 'attendance',
        'branch': 'X',
        'branchId': 'b1',
      }),
      {'legacy': true},
    );
    expect(attendanceQrProof(null), {'legacy': true});
    expect(
      attendanceQrProof({'type': 'attendance', 'sig': 'abc', 'qrVersion': '3'}),
      {'legacy': true},
    );
    expect(
      attendanceQrProof({'type': 'attendance', 'sig': '  ', 'qrVersion': 3}),
      {'legacy': true},
    );
  });

  test(
    'withQrProof keeps the branch identity (equality ignores the proof)',
    () {
      const ref = AttendanceBranchRef(
        branchId: 'b1',
        branchOrganizationUID: 'o1',
        branchName: 'Fake Alpha',
      );
      final withProof = ref.withQrProof(const {'legacy': true});
      expect(withProof, ref);
      expect(withProof.qrProof, {'legacy': true});
      expect(ref.qrProof, isNull);
    },
  );

  test(
    'a new signed QR still parses as the same branch for old code paths',
    () {
      final ref = AttendanceBranchRef.fromQrMap({
        'type': 'attendance',
        'v': 2,
        'branch': 'Fake Alpha',
        'branchId': 'b1',
        'organizationUID': 'o1',
        'qrVersion': 1,
        'sig': 'x',
      }, delegateOrganizationUID: 'o9');
      expect(ref.branchId, 'b1');
      expect(ref.branchOrganizationUID, 'o1');
      expect(ref.branchName, 'Fake Alpha');
    },
  );
}
