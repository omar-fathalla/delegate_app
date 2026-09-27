import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/utils/image_url_helper.dart';

void main() {
  group('ImageUrlHelper Tests', () {
    test('returns empty string for null or empty URL', () {
      expect(ImageUrlHelper.getWebSafeUrl(null), '');
      expect(ImageUrlHelper.getWebSafeUrl(''), '');
      expect(ImageUrlHelper.getWebSafeUrl('   '), '');
    });

    test('returns untouched URL on native non-web test environment', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/photo.jpg?alt=media';
      // In native flutter test (kIsWeb is false)
      final resolved = ImageUrlHelper.getWebSafeUrl(url);
      expect(resolved, url);
    });
  });
}
