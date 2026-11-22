import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-75: clearing a device binding never scans every delegate. An
/// unscoped collection-group list is denied by the rules (and reads every
/// delegate of every company); without an org/company the approved
/// device_unbind_requests doc is left for the server.
void main() {
  test('device_binding_service has no unscoped delegates collection-group get', () {
    final src = File('lib/core/services/device_binding_service.dart').readAsStringSync();
    expect(src, isNot(contains("collectionGroup('delegates').get()")));
  });

  test('the existing public-id lookup is company scoped', () {
    final src = File(
      'lib/features/admin/data/repositories/delegate_subscription_repository_impl.dart',
    ).readAsStringSync();
    final i = src.indexOf("where('nationalId', isEqualTo: cleanNationalId)");
    expect(i, isNonNegative);
    final before = src.substring(i - 200, i);
    expect(before, contains("where('companyUID', isEqualTo: companyUID)"));
  });
}
