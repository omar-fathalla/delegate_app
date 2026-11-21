// TAS-197: a web address with a path and no hash (`/hr/home`) is moved into
// the hash (`/#/hr/home`) before the router reads it, so the router does not
// append its hash to the path (`/hr/home#/hr/home`). Mobile does nothing.
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/web_path_to_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    WebPathToHash.debugReset();
    WebRuntimePolicy.debugReset();
  });

  group('hashAddressForPath', () {
    test('a path without a hash moves into the hash', () {
      expect(hashAddressForPath(path: '/hr/home'), '/#/hr/home');
      expect(hashAddressForPath(path: '/hr/leaves'), '/#/hr/leaves');
      expect(
        hashAddressForPath(path: '/hr/attendance/edits'),
        '/#/hr/attendance/edits',
      );
      expect(hashAddressForPath(path: '/hr/home/'), '/#/hr/home');
      expect(hashAddressForPath(path: '/hr/home', hash: '#'), '/#/hr/home');
      expect(
        hashAddressForPath(path: '/hr/payroll', query: '?inner=1'),
        '/#/hr/payroll?inner=1',
      );
    });

    test('the root, index.html and hash addresses stay', () {
      expect(hashAddressForPath(path: '/'), isNull);
      expect(hashAddressForPath(path: ''), isNull);
      expect(hashAddressForPath(path: '/index.html'), isNull);
      expect(hashAddressForPath(path: '/', hash: '#/hr/home'), isNull);
      // Not a route hash: leave it alone.
      expect(hashAddressForPath(path: '/hr/home', hash: '#token'), isNull);
    });

    test('an address the bug already broke loses the stray path', () {
      expect(
        hashAddressForPath(path: '/hr/home', hash: '#/hr/home'),
        '/#/hr/home',
      );
      expect(
        hashAddressForPath(path: '/hr/home', hash: '#/hr/leaves'),
        '/#/hr/leaves',
      );
    });

    test('a sub-path <base href> is kept', () {
      expect(
        hashAddressForPath(path: '/app/hr/home', base: '/app/'),
        '/app/#/hr/home',
      );
      expect(
        hashAddressForPath(path: '/app/hr/home', base: 'https://h.test/app'),
        '/app/#/hr/home',
      );
      expect(hashAddressForPath(path: '/app/', base: '/app/'), isNull);
      expect(hashAddressForPath(path: '/other/x', base: '/app/'), isNull);
    });
  });

  group('normalizeWebPathToHash', () {
    late List<String> replaced;

    setUp(() {
      replaced = [];
      WebPathToHash.debugReplaceUrl = replaced.add;
    });

    void at(String path, {String query = '', String hash = ''}) =>
        WebPathToHash.debugReadLocation = () =>
            (path: path, query: query, hash: hash, base: '/');

    test('web: /hr/home becomes /#/hr/home', () {
      WebRuntimePolicy.debugIsWebOverride = true;
      at('/hr/home');
      normalizeWebPathToHash();
      expect(replaced, ['/#/hr/home']);
    });

    test('web: a hash address is not touched', () {
      WebRuntimePolicy.debugIsWebOverride = true;
      at('/', hash: '#/hr/leaves');
      normalizeWebPathToHash();
      expect(replaced, isEmpty);
    });

    test('mobile: nothing is read or replaced', () {
      WebRuntimePolicy.debugIsWebOverride = false;
      var reads = 0;
      WebPathToHash.debugReadLocation = () {
        reads++;
        return (path: '/hr/home', query: '', hash: '', base: '/');
      };
      normalizeWebPathToHash();
      expect(reads, 0);
      expect(replaced, isEmpty);
    });
  });
}
