import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEgyptianPhone', () {
    test('accepts the formats already stored for delegates', () {
      expect(normalizeEgyptianPhone('+20 123 456 7890'), '01234567890');
      expect(normalizeEgyptianPhone('00201234567890'), '01234567890');
      expect(normalizeEgyptianPhone('1234567890'), '01234567890');
      expect(normalizeEgyptianPhone('٠١٢٣٤٥٦٧٨٩٠'), '01234567890');
      expect(normalizeEgyptianPhone('01234567890'), '01234567890');
    });
  });

  group('validateLoginPhone', () {
    test('requires a value and an Egyptian mobile', () {
      expect(
        validateLoginPhone('', emptyMessage: 'empty', invalidMessage: 'bad'),
        'empty',
      );
      expect(
        validateLoginPhone('123', emptyMessage: 'empty', invalidMessage: 'bad'),
        'bad',
      );
      expect(
        validateLoginPhone(
          '+201234567890',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
    });
  });

  group('validateLoginSecret', () {
    test('requires a national ID and accepts a staff password', () {
      expect(
        validateLoginSecret(null, emptyMessage: 'empty', invalidMessage: 'bad'),
        'empty',
      );
      expect(
        validateLoginSecret('123', emptyMessage: 'empty', invalidMessage: 'bad'),
        'bad',
      );
      expect(
        validateLoginSecret(
          '29712200201981',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
      expect(
        validateLoginSecret(
          'StaffPass1',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
    });
  });

  test('phone variants include the international forms', () {
    final variants = egyptianPhoneVariants('01234567890');
    expect(variants, contains('01234567890'));
    expect(variants, contains('+201234567890'));
    expect(variants, contains('201234567890'));
  });
}
