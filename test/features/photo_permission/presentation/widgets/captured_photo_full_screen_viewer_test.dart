import 'dart:io';

import 'package:delegate_app/features/photo_permission/presentation/widgets/captured_photo_full_screen_viewer.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

/// TAS-302: full-screen check of a stamped photo before sending.
void main() {
  late Directory dir;
  late File photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tas302_viewer_');
    final image = img.Image(width: 30, height: 40);
    photo = File('${dir.path}/p.jpg')..writeAsBytesSync(img.encodeJpg(image));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<CapturedPhotoViewerAction?> openAndTap(WidgetTester tester, Key? key) async {
    CapturedPhotoViewerAction? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await CapturedPhotoFullScreenViewer.open(
                context,
                photo: photo,
                photoNumber: 2,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('captured_photo_viewer_image')), findsOneWidget);
    expect(find.text('صورة 2'), findsOneWidget);
    expect(find.text('إعادة الالتقاط'), findsOneWidget);

    if (key != null) {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    }
    return result;
  }

  testWidgets('retake returns retake', (tester) async {
    expect(
      await openAndTap(tester, const ValueKey('captured_photo_viewer_retake')),
      CapturedPhotoViewerAction.retake,
    );
  });

  testWidgets('delete returns delete', (tester) async {
    expect(
      await openAndTap(tester, const ValueKey('captured_photo_viewer_delete')),
      CapturedPhotoViewerAction.delete,
    );
  });

  testWidgets('close returns null', (tester) async {
    expect(
      await openAndTap(tester, const ValueKey('captured_photo_viewer_close')),
      isNull,
    );
  });
}
