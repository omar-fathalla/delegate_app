import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DelegateProfileCache.clearSession();
  });

  test('session + persistent round-trip for immutable fields', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = DelegateProfileCache(prefs: prefs);
    cache.putFromMaps(
      delegateId: 'd1',
      fullName: 'Name One',
      phoneNumber: '0100',
      personalPhotoURL: 'https://x/y.jpg',
      companyName: 'Co',
      companyUID: 'c1',
      organizationUID: 'o1',
    );
    await cache.persist();
    DelegateProfileCache.clearSession();

    final cache2 = DelegateProfileCache(prefs: prefs);
    final got = cache2.get('d1');
    expect(got, isNotNull);
    expect(got!.fullName, 'Name One');
    expect(got.phoneNumber, '0100');
    expect(got.personalPhotoURL, 'https://x/y.jpg');
    expect(got.effectiveCompanyName, 'Co');
  });

  test('companyName expires after 24h TTL; name/phone/photo do not', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = DelegateProfileCache(prefs: prefs);
    final oldMs = DateTime.now()
        .subtract(const Duration(hours: 25))
        .millisecondsSinceEpoch;
    cache.put(
      'd2',
      CachedDelegateProfile(
        fullName: 'Forever Name',
        phoneNumber: '0111',
        personalPhotoURL: 'https://x/z.jpg',
        companyName: 'Old Co',
        companyUID: 'c2',
        companyNameCachedAtMs: oldMs,
      ),
    );
    final got = cache.get('d2')!;
    expect(got.fullName, 'Forever Name');
    expect(got.phoneNumber, '0111');
    expect(got.hasUsablePhoto, isTrue);
    expect(got.effectiveCompanyName, isEmpty);
  });
}
