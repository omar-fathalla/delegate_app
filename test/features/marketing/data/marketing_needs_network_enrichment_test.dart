import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('marketingNeedsNetworkEnrichment', () {
    test('skips network when name and phone are present even without photo', () {
      expect(
        marketingNeedsNetworkEnrichment(hasName: true, hasPhone: true),
        isFalse,
      );
    });

    test('needs network when name missing', () {
      expect(
        marketingNeedsNetworkEnrichment(hasName: false, hasPhone: true),
        isTrue,
      );
    });

    test('needs network when phone missing', () {
      expect(
        marketingNeedsNetworkEnrichment(hasName: true, hasPhone: false),
        isTrue,
      );
    });
  });
}
