import 'dart:typed_data';

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

void main() {
  tearDown(() {
    TaskImageFetcher.debugOverride = null;
  });

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
}
