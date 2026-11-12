import 'dart:io';
import 'dart:typed_data';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFetcher extends TaskImageFetcher {
  _RecordingFetcher(this.bytes);
  final Uint8List bytes;
  final calls = <Map<String, String?>>[];

  @override
  Future<Uint8List> load({
    required String imagePath,
    String? taskId,
    String? organizationId,
  }) async {
    calls.add({
      'imagePath': imagePath,
      'taskId': taskId,
      'organizationId': organizationId,
    });
    return bytes;
  }
}

/// 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _RecordingStorage extends TaskImageStorage {
  final deleted = <String>[];
  String nextPath = 'task_images/c1/sup-1/task_sup-1_new.jpg';

  @override
  Future<TaskImageUpload> upload({
    required String companyId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    return TaskImageUpload(url: '', path: nextPath);
  }

  @override
  Future<void> deleteQuietly(String path) async {
    deleted.add(path);
  }
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}

void _attachOverrides(_RecordingStorage storage) {
  TaskImageFetcher.debugOverride = _RecordingFetcher(_png);
  TaskImagePickerField.debugStorageOverride = storage;
}

void main() {
  tearDown(() {
    TaskImageFetcher.debugOverride = null;
    TaskImagePickerField.debugStorageOverride = null;
    TaskImagePickerField.debugPickerOverride = null;
  });

  test(
    'edit mode does not delete the saved object after a replacement is chosen or Remove is tapped',
    () {
      const original = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      const replacement = 'task_images/c1/sup-1/task_sup-1_new.jpg';
      expect(
        TaskImagePickerField.shouldDeleteStoredImageNow(
          deleteStorageImmediately: false,
          previousPath: original,
          nextPath: replacement,
        ),
        isFalse,
      );
      expect(
        TaskImagePickerField.shouldDeleteStoredImageNow(
          deleteStorageImmediately: false,
          previousPath: original,
        ),
        isFalse,
      );
      expect(
        TaskImagePickerField.shouldDeleteStoredImageNow(
          deleteStorageImmediately: true,
          previousPath: original,
          nextPath: replacement,
        ),
        isTrue,
      );
      expect(
        TaskImagePickerField.shouldDeleteStoredImageNow(
          deleteStorageImmediately: true,
          previousPath: original,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'thumbnail loads through the fetcher with path and task id, not a URL',
    (tester) async {
      final fetcher = _RecordingFetcher(_png);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskImageThumbnail(
              imagePath: 'task_images/c1/sup-1/task_sup-1_1.jpg',
              taskId: 't1',
              organizationId: 'o1',
              fetcher: fetcher,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fetcher.calls, hasLength(1));
      expect(
        fetcher.calls.single['imagePath'],
        'task_images/c1/sup-1/task_sup-1_1.jpg',
      );
      expect(fetcher.calls.single['taskId'], 't1');
      expect(fetcher.calls.single['organizationId'], 'o1');
      expect(fetcher.calls.single['imagePath']!.startsWith('http'), isFalse);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'edit picker does not delete the saved image on Remove or after cancel',
    (tester) async {
      final storage = _RecordingStorage();
      _attachOverrides(storage);
      const original = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      await tester.pumpWidget(
        _app(
          TaskImagePickerField(
            organizationId: 'o1',
            companyId: 'c1',
            initialPath: original,
            initialTaskId: 't1',
            deleteStorageImmediately: false,
            storage: storage,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Symbols.delete_rounded));
      await tester.pumpAndSettle();
      expect(storage.deleted, isEmpty);

      // Dropping the route (cancel / abandon) still leaves the original.
      await tester.pumpWidget(_app(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(storage.deleted, isEmpty);
    },
  );

  testWidgets('create picker still deletes immediately when Remove is tapped', (
    tester,
  ) async {
    final storage = _RecordingStorage();
    _attachOverrides(storage);
    const original = 'task_images/c1/sup-1/task_sup-1_1.jpg';
    await tester.pumpWidget(
      _app(
        TaskImagePickerField(
          organizationId: 'o1',
          companyId: 'c1',
          initialPath: original,
          deleteStorageImmediately: true,
          storage: storage,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.delete_rounded));
    await tester.pumpAndSettle();
    expect(storage.deleted, [original]);
  });
}
