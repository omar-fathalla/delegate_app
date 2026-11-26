import 'package:cached_network_image/cached_network_image.dart';
import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/widgets/storage_resolved_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-42: a stored Storage path is shown through a URL resolved at read
/// time; an old download URL is shown as it is.
void main() {
  tearDown(() => StorageMediaResolver.debugOverride = null);

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)));

  group('StorageResolvedImage', () {
    testWidgets('a path is resolved before the builder runs', (tester) async {
      final resolver = StorageMediaResolver(
        downloadUrlFor: (p) async => 'https://signed.example/$p',
      );
      await tester.pumpWidget(host(StorageResolvedImage(
        pathOrUrl: 'leave_attachments/co/d/1.jpg',
        resolver: resolver,
        builder: (_, url) => Text(url),
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('https://signed.example/leave_attachments/co/d/1.jpg'),
          findsOneWidget);
    });

    testWidgets('an old URL is passed through unchanged', (tester) async {
      var calls = 0;
      final resolver = StorageMediaResolver(downloadUrlFor: (_) async {
        calls++;
        return 'never';
      });
      await tester.pumpWidget(host(StorageResolvedImage(
        pathOrUrl: 'https://old.example/x.jpg',
        resolver: resolver,
        builder: (_, url) => Text(url),
      )));
      await tester.pumpAndSettle();
      expect(find.text('https://old.example/x.jpg'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('a denied path shows the error widget', (tester) async {
      final resolver = StorageMediaResolver(
        downloadUrlFor: (_) async =>
            throw FirebaseException(plugin: 'storage', code: 'unauthorized'),
      );
      await tester.pumpWidget(host(StorageResolvedImage(
        pathOrUrl: 'penalties/co/evidence/p/1.jpg',
        resolver: resolver,
        error: const Text('denied'),
        builder: (_, url) => Text(url),
      )));
      await tester.pumpAndSettle();
      expect(find.text('denied'), findsOneWidget);
    });

    testWidgets('a cached path renders at once', (tester) async {
      final resolver = StorageMediaResolver(
        downloadUrlFor: (p) async => 'https://signed.example/$p',
      );
      await resolver.resolve('a/b.jpg');
      await tester.pumpWidget(host(StorageResolvedImage(
        pathOrUrl: 'a/b.jpg',
        resolver: resolver,
        builder: (_, url) => Text(url),
      )));
      expect(find.text('https://signed.example/a/b.jpg'), findsOneWidget);
    });
  });

  group('AppPhotoImage', () {
    testWidgets('a Storage path loads the resolved URL, keyed by the path',
        (tester) async {
      StorageMediaResolver.debugOverride = StorageMediaResolver(
        downloadUrlFor: (p) async => 'https://signed.example/$p',
      );
      const path = 'organizations/o/companies/c/permissions/p/photo_d_1.jpg';
      await tester.pumpWidget(host(const AppPhotoImage(photoUrl: path)));
      for (var i = 0;
          i < 40 && find.byType(CachedNetworkImage).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://signed.example/$path');
      expect(image.cacheKey, path);
    });

    testWidgets('an old URL is loaded directly', (tester) async {
      var calls = 0;
      StorageMediaResolver.debugOverride = StorageMediaResolver(
        downloadUrlFor: (_) async {
          calls++;
          return 'never';
        },
      );
      await tester.pumpWidget(
          host(const AppPhotoImage(photoUrl: 'https://old.example/x.jpg')));
      await tester.pump();

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://old.example/x.jpg');
      expect(image.cacheKey, isNull);
      expect(calls, 0);
    });
  });
}
