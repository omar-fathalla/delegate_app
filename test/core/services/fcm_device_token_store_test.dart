// TAS-258: per-device FCM tokens. The legacy fcm_tokens/{uid} doc is still
// written as before; each install also writes fcm_tokens/{uid}/devices/{id}.
// Logout removes only this install's doc, and the legacy doc only when it
// still holds this install's token.
import 'package:delegate_app/core/services/fcm_device_token_store.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore db;
  FcmDeviceTokenStore store(String deviceId, {String platform = 'android'}) =>
      FcmDeviceTokenStore(
        firestore: db,
        deviceId: () async => deviceId,
        platform: platform,
      );
  Future<Map<String, dynamic>?> read(String path) async =>
      (await db.doc(path).get()).data();

  setUp(() => db = FakeFirebaseFirestore());

  test('save writes the legacy doc and this device doc', () async {
    await store('dev-a').save('u1', 'tok-a');
    final legacy = await read('fcm_tokens/u1');
    expect(legacy?['token'], 'tok-a');
    expect(legacy?['platform'], 'android');
    expect(legacy?.containsKey('updatedAt'), isTrue);
    final device = await read('fcm_tokens/u1/devices/dev-a');
    expect(device?['token'], 'tok-a');
    expect(device?['platform'], 'android');
    expect(device?.keys.toSet(), {'token', 'platform', 'updatedAt'});
  });

  test('token refresh updates the same device doc', () async {
    final a = store('dev-a');
    await a.save('u1', 'tok-a');
    await a.save('u1', 'tok-a2');
    final devices = await db.collection('fcm_tokens/u1/devices').get();
    expect(devices.docs.map((d) => d.id), ['dev-a']);
    expect(devices.docs.single.data()['token'], 'tok-a2');
    expect((await read('fcm_tokens/u1'))?['token'], 'tok-a2');
  });

  test('two devices keep two device docs', () async {
    await store('dev-a').save('u1', 'tok-a');
    await store('dev-b', platform: 'ios').save('u1', 'tok-b');
    final devices = await db.collection('fcm_tokens/u1/devices').get();
    expect(devices.docs.map((d) => d.id).toSet(), {'dev-a', 'dev-b'});
    // Legacy keeps the last writer, exactly as before.
    expect((await read('fcm_tokens/u1'))?['token'], 'tok-b');
  });

  test('logout on the older device keeps the other device and legacy',
      () async {
    final a = store('dev-a');
    await a.save('u1', 'tok-a');
    await store('dev-b').save('u1', 'tok-b');

    await a.clear('u1');

    expect(await read('fcm_tokens/u1/devices/dev-a'), isNull);
    expect((await read('fcm_tokens/u1/devices/dev-b'))?['token'], 'tok-b');
    expect((await read('fcm_tokens/u1'))?['token'], 'tok-b');
  });

  test('logout on the device that wrote legacy deletes both its docs',
      () async {
    await store('dev-a').save('u1', 'tok-a');
    final b = store('dev-b');
    await b.save('u1', 'tok-b');

    await b.clear('u1');

    expect(await read('fcm_tokens/u1/devices/dev-b'), isNull);
    expect(await read('fcm_tokens/u1'), isNull);
    expect((await read('fcm_tokens/u1/devices/dev-a'))?['token'], 'tok-a');
  });

  test('legacy written by an old app version on another device is kept',
      () async {
    final a = store('dev-a');
    await a.save('u1', 'tok-a');
    // Old app version elsewhere: legacy only.
    await db.doc('fcm_tokens/u1').set({'token': 'tok-old-app'});

    await a.clear('u1');

    expect(await read('fcm_tokens/u1/devices/dev-a'), isNull);
    expect((await read('fcm_tokens/u1'))?['token'], 'tok-old-app');
  });

  test('device doc missing: falls back to the token saved in memory',
      () async {
    final a = store('dev-a');
    await a.save('u1', 'tok-a');
    await db.doc('fcm_tokens/u1/devices/dev-a').delete();

    await a.clear('u1');

    expect(await read('fcm_tokens/u1'), isNull);
  });

  test('own token unknown: legacy is deleted as before (no stale pushes)',
      () async {
    await db.doc('fcm_tokens/u1').set({'token': 'tok-x'});
    await store('dev-a').clear('u1');
    expect(await read('fcm_tokens/u1'), isNull);
  });

  test('empty uid or token writes nothing', () async {
    final a = store('dev-a');
    await a.save('', 'tok');
    await a.save('u1', '');
    await a.clear('');
    expect((await db.collection('fcm_tokens').get()).docs, isEmpty);
  });

  test('install id is random once, then stable', () async {
    SharedPreferences.setMockInitialValues({});
    FcmInstallId.resetCache();
    final first = await FcmInstallId.load();
    FcmInstallId.resetCache();
    final again = await FcmInstallId.load();
    expect(first, isNotEmpty);
    expect(first.contains('/'), isFalse);
    expect(again, first);
    FcmInstallId.resetCache();
  });
}
