/// Arabic-Indic and Persian digits as Western digits.
///
/// Date formats and some Arabic fonts substitute ٠–٩. Phone numbers and the
/// header date stay in Western digits so they match the rest of the web shell.
String hrWesternDigits(String value) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    final easternIndex = eastern.indexOf(ch);
    if (easternIndex >= 0) {
      buffer.write(easternIndex);
      continue;
    }
    final persianIndex = persian.indexOf(ch);
    if (persianIndex >= 0) {
      buffer.write(persianIndex);
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}
