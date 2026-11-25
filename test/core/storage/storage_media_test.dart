import 'dart:async';

import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockRef extends Mock implements Reference {}

const _legacyUrl =
    'https://firebasestorage.googleapis.com/v0/b/tashil-dev.firebasestorage.app/o/'
    'leave_attachments%2Fco1%2Fd1%2F1_a.jpg?alt=media&token=fake-token';

/// TAS-42: stored values are a Storage path (new) or a download URL (old).
void main() {
  tearDown(() {
    StorageMediaRef.clearLegacyUrls();
    LegacyStorageUrls.debugOverride = null;
    StorageMediaResolver.debugOverride = null;
  });

  group('StorageMediaRef.isStoragePath', () {
    test('object paths and gs:// are Storage paths', () {
      expect(StorageMediaRef.isStoragePath('feedback_screenshots/a.jpg'), isTrue);
      expect(StorageMediaRef.isStoragePath('penalties/co/evidence/p/1_a.pdf'), isTrue);
      expect(StorageMediaRef.isStoragePath('gs://bucket/a/b.jpg'), isTrue);
    });

    test('URLs, local files, assets and empty values are not', () {
      for (final v in <String?>[
        null,
        '',
        '   ',
        _legacyUrl,
        'http://x/y.jpg',
        '/data/user/0/app/files/x.jpg',
        '/var/mobile/Containers/x.jpg',
        'file:///tmp/x.jpg',
        'content://media/1',
        'assets/images/private_label/wixmax.jpg',
        r'C:\Users\x.jpg',
        'x.jpg',
      ]) {
        expect(StorageMediaRef.isStoragePath(v), isFalse, reason: '$v');
      }
    });
  });

  group('StorageMediaRef.pick', () {
    test('prefers the path, falls back to the URL, else empty', () {
      expect(StorageMediaRef.pick(path: 'a/b.jpg', url: _legacyUrl), 'a/b.jpg');
      expect(StorageMediaRef.pick(path: '', url: _legacyUrl), _legacyUrl);
      expect(StorageMediaRef.pick(path: null, url: null), '');
      expect(StorageMediaRef.pick(path: 7, url: ' u '), 'u');
    });
  });

  test('pathFromDownloadUrl decodes the object path', () {
    expect(StorageMediaRef.pathFromDownloadUrl(_legacyUrl),
        'leave_attachments/co1/d1/1_a.jpg');
    expect(StorageMediaRef.pathFromDownloadUrl('https://cdn.example/x.jpg'), isNull);
    expect(StorageMediaRef.pathFromDownloadUrl('a/b.jpg'), isNull);
  });

  group('StorageMediaRef.refFor', () {
    test('path -> ref(), URL -> refFromURL(), local -> null', () {
      final storage = _MockStorage();
      final byPath = _MockRef();
      final byUrl = _MockRef();
      when(() => storage.ref('a/b.jpg')).thenReturn(byPath);
      when(() => storage.refFromURL(_legacyUrl)).thenReturn(byUrl);

      expect(StorageMediaRef.refFor(storage, 'a/b.jpg'), same(byPath));
      expect(StorageMediaRef.refFor(storage, _legacyUrl), same(byUrl));
      expect(StorageMediaRef.refFor(storage, '/data/x.jpg'), isNull);
      expect(StorageMediaRef.refFor(storage, ''), isNull);
    });

    test('an unparsable URL gives null instead of throwing', () {
      final storage = _MockStorage();
      when(() => storage.refFromURL(any())).thenThrow(ArgumentError('bad'));
      expect(StorageMediaRef.refFor(storage, 'https://cdn.example/x.jpg'), isNull);
    });
  });

  group('StorageMediaResolver', () {
    test('URLs, local files and assets pass through without a lookup', () async {
      var calls = 0;
      final r = StorageMediaResolver(downloadUrlFor: (_) async {
        calls++;
        return 'never';
      });
      expect(await r.resolve(_legacyUrl), _legacyUrl);
      expect(await r.resolve('/data/x.jpg'), '/data/x.jpg');
      expect(await r.resolve('assets/a.jpg'), 'assets/a.jpg');
      expect(await r.resolve(''), isNull);
      expect(await r.resolve(null), isNull);
      expect(calls, 0);
    });

    test('a path is resolved once and cached; concurrent calls share it', () async {
      var calls = 0;
      final gate = Completer<String>();
      final r = StorageMediaResolver(downloadUrlFor: (p) {
        calls++;
        return gate.future;
      });
      final a = r.resolve('a/b.jpg');
      final b = r.resolve('a/b.jpg');
      gate.complete('https://signed/a');
      expect(await a, 'https://signed/a');
      expect(await b, 'https://signed/a');
      expect(await r.resolve('a/b.jpg'), 'https://signed/a');
      expect(r.cachedUrl('a/b.jpg'), 'https://signed/a');
      expect(calls, 1);
    });

    test('a failure is not cached, so the next call retries', () async {
      var calls = 0;
      final r = StorageMediaResolver(downloadUrlFor: (p) async {
        calls++;
        if (calls == 1) throw FirebaseException(plugin: 'storage', code: 'unauthorized');
        return 'https://signed/ok';
      });
      await expectLater(r.resolve('a/b.jpg'), throwsA(isA<FirebaseException>()));
      expect(r.cachedUrl('a/b.jpg'), isNull);
      expect(await r.tryResolve('a/b.jpg'), 'https://signed/ok');
      expect(calls, 2);
    });

    test('a denied path falls back to the URL its doc also carried', () async {
      var calls = 0;
      final r = StorageMediaResolver(downloadUrlFor: (_) async {
        calls++;
        throw FirebaseException(plugin: 'storage', code: 'unauthorized');
      });
      expect(StorageMediaRef.pick(path: 'x/y.jpg', url: _legacyUrl), 'x/y.jpg');
      expect(await r.resolve('x/y.jpg'), _legacyUrl);
      expect(await r.resolve('x/y.jpg'), _legacyUrl);
      expect(calls, 1);
    });

    test('an allowed path is used even when a legacy URL exists', () async {
      final r = StorageMediaResolver(downloadUrlFor: (p) async => 'https://signed/$p');
      StorageMediaRef.pick(path: 'x/y.jpg', url: _legacyUrl);
      expect(await r.resolve('x/y.jpg'), 'https://signed/x/y.jpg');
    });

    test('tryResolve returns null when the rules deny the read', () async {
      final r = StorageMediaResolver(
        downloadUrlFor: (_) async =>
            throw FirebaseException(plugin: 'storage', code: 'unauthorized'),
      );
      expect(await r.tryResolve('delegate_documents/x/p.jpg'), isNull);
    });

    test('entries expire after the ttl', () async {
      var now = DateTime(2026, 11, 25, 10);
      var calls = 0;
      final r = StorageMediaResolver(
        downloadUrlFor: (_) async => 'https://signed/${++calls}',
        ttl: const Duration(minutes: 10),
        now: () => now,
      );
      expect(await r.resolve('a/b.jpg'), 'https://signed/1');
      now = now.add(const Duration(minutes: 11));
      expect(r.cachedUrl('a/b.jpg'), isNull);
      expect(await r.resolve('a/b.jpg'), 'https://signed/2');
    });

    test('the cache is bounded', () async {
      final r = StorageMediaResolver(
        downloadUrlFor: (p) async => 'https://signed/$p',
        maxEntries: 3,
      );
      for (var i = 0; i < 6; i++) {
        await r.resolve('a/$i.jpg');
      }
      expect(r.cacheSize, lessThanOrEqualTo(3));
      expect(r.cachedUrl('a/5.jpg'), 'https://signed/a/5.jpg');
    });

    test('instance honours debugOverride', () {
      final fake = StorageMediaResolver(downloadUrlFor: (_) async => 'x');
      StorageMediaResolver.debugOverride = fake;
      expect(StorageMediaResolver.instance, same(fake));
    });
  });

  group('LegacyStorageUrls', () {
    test('defaults to on when Remote Config is unavailable', () {
      expect(LegacyStorageUrls.enabled, isTrue);
    });

    test('urlFor returns the download URL while on', () async {
      final ref = _MockRef();
      when(() => ref.getDownloadURL()).thenAnswer((_) async => _legacyUrl);
      LegacyStorageUrls.debugOverride = true;
      expect(await LegacyStorageUrls.urlFor(ref), _legacyUrl);
    });

    test('urlFor skips the lookup while off', () async {
      final ref = _MockRef();
      LegacyStorageUrls.debugOverride = false;
      expect(await LegacyStorageUrls.urlFor(ref), isNull);
      verifyNever(() => ref.getDownloadURL());
    });

    test('a failed lookup does not fail the upload', () async {
      final ref = _MockRef();
      when(() => ref.getDownloadURL()).thenThrow(Exception('offline'));
      LegacyStorageUrls.debugOverride = true;
      expect(await LegacyStorageUrls.urlFor(ref), isNull);
    });
  });
}
