// TAS-112: the country is picked (Egypt by default), the number is typed.
import 'package:delegate_app/features/auth/domain/phone_country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Egypt: with or without the leading 0', () {
    expect(composePhone(PhoneCountry.egypt, '1211857725'), '01211857725');
    expect(composePhone(PhoneCountry.egypt, '01211857725'), '01211857725');
    expect(composePhone(PhoneCountry.egypt, '201211857725'), '01211857725');
    expect(composePhone(PhoneCountry.egypt, '١٢١١٨٥٧٧٢٥'), '01211857725');
  });

  test('UAE: with or without the leading 0', () {
    expect(composePhone(PhoneCountry.uae, '501234567'), '0501234567');
    expect(composePhone(PhoneCountry.uae, '0501234567'), '0501234567');
    expect(composePhone(PhoneCountry.uae, '971501234567'), '0501234567');
  });

  test('a typed international number wins over the picker', () {
    expect(composePhone(PhoneCountry.egypt, '+971501234567'), '0501234567');
    expect(composePhone(PhoneCountry.uae, '+201211857725'), '01211857725');
  });

  test('empty stays empty', () => expect(composePhone(PhoneCountry.uae, '  '), ''));

  test('country of a stored number and its local part', () {
    expect(PhoneCountry.of('0501234567'), PhoneCountry.uae);
    expect(PhoneCountry.of('01211857725'), PhoneCountry.egypt);
    expect(localPart('0501234567'), '501234567');
    expect(localPart('01211857725'), '1211857725');
  });
}
