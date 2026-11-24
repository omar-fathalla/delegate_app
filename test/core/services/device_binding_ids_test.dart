// TAS-261: Android binds on ANDROID_ID (aid_...), the old Build.ID still
// matches an old binding until the server moves it.
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('androidIds', () {
    test('ANDROID_ID becomes the device id, Build.ID the legacy id', () {
      expect(
        DeviceBindingService.androidIds(androidId: 'abc123', buildId: 'TP1A.220624.014'),
        {'deviceId': 'aid_abc123', 'legacyDeviceId': 'TP1A.220624.014'},
      );
    });
    test('no ANDROID_ID keeps Build.ID as the device id', () {
      expect(
        DeviceBindingService.androidIds(androidId: '', buildId: 'TP1A.220624.014'),
        {'deviceId': 'TP1A.220624.014', 'legacyDeviceId': ''},
      );
    });
  });

  group('isSameDevice', () {
    test('new binding matches the new id', () {
      expect(DeviceBindingService.isSameDevice(
          boundDeviceId: 'aid_abc123', currentDeviceId: 'aid_abc123', legacyDeviceId: 'TP1A'), isTrue);
    });
    test('old Build.ID binding matches through the legacy id', () {
      expect(DeviceBindingService.isSameDevice(
          boundDeviceId: 'TP1A.220624.014', currentDeviceId: 'aid_abc123', legacyDeviceId: 'TP1A.220624.014'), isTrue);
    });
    test('another phone does not match', () {
      expect(DeviceBindingService.isSameDevice(
          boundDeviceId: 'aid_other', currentDeviceId: 'aid_abc123', legacyDeviceId: 'aid_other'), isFalse);
      expect(DeviceBindingService.isSameDevice(
          boundDeviceId: 'UP1A.231005.007', currentDeviceId: 'aid_abc123', legacyDeviceId: 'TP1A.220624.014'), isFalse);
    });
    test('an empty binding is not a match', () {
      expect(DeviceBindingService.isSameDevice(boundDeviceId: '', currentDeviceId: 'aid_abc123'), isFalse);
    });
  });
}
