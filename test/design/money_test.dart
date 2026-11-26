import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/design/money.dart';

void main() {
  test('formats piastres with grouping and two decimals', () {
    expect(Money.amount(0), '0.00');
    expect(Money.amount(5), '0.05');
    expect(Money.amount(125050), '1,250.50');
    expect(Money.amount(-100000000), '-1,000,000.00');
    expect(Money.format(4550), '45.50 ج.م');
  });

  test('formats quantities without trailing zeros', () {
    expect(Money.qty(2), '2');
    expect(Money.qty(1.25), '1.25');
    expect(Money.qty(0.5), '0.5');
  });
}
