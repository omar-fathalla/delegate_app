// TAS-214: «بيت الجملة» contains «جملة» and used to show as «جملة ماركت».
import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Beit El Gomla is matched before Gomla Market', () {
    expect(chainKeyOf('بيت الجملة'), ChainKey.beitElGomla);
    expect(chainKeyOf('سوبر ماركت بيت الجملة'), ChainKey.beitElGomla);
    expect(chainKeyOf('Beit El Gomla'), ChainKey.beitElGomla);
    expect(chainDisplayName('بيت الجملة'), 'بيت الجملة');
    expect(chainDisplayName('بيت الجملة', isArabic: false), 'Beit El Gomla');
  });

  test('other chains keep their names', () {
    expect(chainDisplayName('جملة ماركت'), 'جملة ماركت');
    expect(chainDisplayName('Gomla Market'), 'جملة ماركت');
    expect(chainDisplayName('فتح الله (تجريبي)'), 'فتح الله ماركت');
    expect(chainDisplayName('zahran'), 'زهران ماركت');
    expect(chainDisplayName('كارفور', isArabic: false), 'Carrefour');
    expect(chainDisplayName('  مترو  '), 'مترو');
  });
}
