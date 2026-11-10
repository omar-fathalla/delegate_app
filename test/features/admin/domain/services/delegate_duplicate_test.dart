import 'package:delegate_app/features/admin/domain/services/delegate_duplicate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('another_company names the company and asks to delete him first', () {
    final result = DelegateDuplicateResult.fromMap({
      'duplicate': true,
      'reason': 'another_company',
      'companyName': 'شركة النور',
    });
    expect(
      result.message(),
      'مسجل بالفعل في شركة: شركة النور. يرجى حذفه منها أولاً.',
    );
  });

  test('another_company without a name still asks to delete first', () {
    final result = DelegateDuplicateResult.fromMap({
      'duplicate': true,
      'reason': 'another_company',
    });
    expect(
      result.message(),
      'مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً.',
    );
  });

  test('same_company does not surface another company name', () {
    final result = DelegateDuplicateResult.fromMap({
      'duplicate': true,
      'reason': 'same_company',
      'companyName': 'SHOULD_NOT_APPEAR',
    });
    expect(result.message(), isNot(contains('SHOULD_NOT_APPEAR')));
    expect(result.message(), contains('هذه الشركة'));
  });

  test('available payload has no message and ignores extra fields', () {
    final result = DelegateDuplicateResult.fromMap({
      'duplicate': false,
      'companyUID': 'c2',
      'delegateName': 'secret',
    });
    expect(result.duplicate, isFalse);
    expect(result.message(), isNull);
  });
}
