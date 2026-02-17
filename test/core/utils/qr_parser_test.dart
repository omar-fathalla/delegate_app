import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/utils/qr_parser.dart';

void main() {
  group('parseBranchFromQr', () {
    test('returns branch name for valid attendance QR code', () {
      const rawValue = '{"type": "attendance", "branch": "Smouha"}';
      expect(parseBranchFromQr(rawValue), 'Smouha');
    });

    test('returns null for invalid JSON', () {
      const rawValue = '{not valid json}';
      expect(parseBranchFromQr(rawValue), null);
    });

    test('returns null for JSON with wrong type', () {
      const rawValue = '{"type": "other", "branch": "Smouha"}';
      expect(parseBranchFromQr(rawValue), null);
    });

    test('returns null for JSON without branch key', () {
      const rawValue = '{"type": "attendance"}';
      expect(parseBranchFromQr(rawValue), null);
    });

    test('returns null for JSON where branch is not a string', () {
      const rawValue = '{"type": "attendance", "branch": 123}';
      expect(parseBranchFromQr(rawValue), null);
    });
  });
}
