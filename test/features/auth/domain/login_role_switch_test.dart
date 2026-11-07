import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? nid(String? v) => validateDelegateNationalId(v,
      emptyMessage: 'empty', invalidMessage: 'invalid');
  String? pw(String? v) => validateStaffPassword(v, emptyMessage: 'empty');

  group('validateDelegateNationalId', () {
    test('accepts exactly 14 digits, including Arabic digits', () {
      expect(nid('29001011234567'), isNull);
      expect(nid('٢٩٠٠١٠١١٢٣٤٥٦٧'), isNull);
    });
    test('rejects empty, short, long, and letters', () {
      expect(nid(''), 'empty');
      expect(nid('2900101123456'), 'invalid');
      expect(nid('290010112345678'), 'invalid');
      expect(nid('abcd1234567890'), 'invalid');
    });
  });

  group('validateStaffPassword', () {
    test('accepts any non-empty value, including all digits', () {
      expect(pw('123456'), isNull);
      expect(pw('Pass@word1'), isNull);
    });
    test('rejects empty or blank', () {
      expect(pw(null), 'empty');
      expect(pw('   '), 'empty');
    });
  });

  group('supervisor role parsing', () {
    for (final r in [
      'supervisor', 'company_supervisor', 'companySupervisor',
      'company-supervisor', 'COMPANY_SUPERVISOR',
    ]) {
      test('$r counts as supervisor', () {
        expect(AuthRemoteDataSourceImpl.isSupervisorRole(r), isTrue);
        expect(AuthRemoteDataSourceImpl.staffRoleWeightForTest(r), 60);
      });
    }
    test('delegate is not staff', () {
      expect(AuthRemoteDataSourceImpl.isSupervisorRole('delegate'), isFalse);
      expect(AuthRemoteDataSourceImpl.staffRoleWeightForTest('delegate'), 0);
    });
  });
}
