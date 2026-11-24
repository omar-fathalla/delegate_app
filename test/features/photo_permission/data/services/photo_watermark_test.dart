import 'dart:io';
import 'dart:typed_data';

import 'package:delegate_app/features/photo_permission/data/services/photo_watermark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// TAS-302: field photos carry the branch and capture time in their pixels.
void main() {
  group('PhotoWatermark.formatStamp', () {
    test('morning time uses ص and pads day, month and minutes', () {
      expect(
        PhotoWatermark.formatStamp(DateTime(2026, 3, 5, 9, 7)),
        '05/03/2026  9:07 ص',
      );
    });

    test('afternoon time is 12-hour with م', () {
      expect(
        PhotoWatermark.formatStamp(DateTime(2026, 11, 24, 15, 30)),
        '24/11/2026  3:30 م',
      );
    });

    test('midnight and noon show 12', () {
      expect(PhotoWatermark.formatStamp(DateTime(2026, 1, 1, 0, 0)), '01/01/2026  12:00 ص');
      expect(PhotoWatermark.formatStamp(DateTime(2026, 1, 1, 12, 0)), '01/01/2026  12:00 م');
    });
  });

  group('PhotoWatermark.stampBytes', () {
    /// A plain white JPEG, so any dark pixel comes from the stamp.
    List<int> whiteJpeg(int width, int height, {int? exifOrientation}) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      if (exifOrientation != null) {
        image.exif.imageIfd.orientation = exifOrientation;
      }
      return img.encodeJpg(image, quality: 95);
    }

    double meanLuma(img.Image image, int y0, int y1) {
      var sum = 0.0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = 0; x < image.width; x++) {
          sum += image.getPixel(x, y).luminanceNormalized;
          n++;
        }
      }
      return sum / n;
    }

    testWidgets('keeps the size and darkens only the bottom strip', (tester) async {
      await tester.runAsync(() async {
        final source = whiteJpeg(600, 800);
        final out = await PhotoWatermark.stampBytes(
          Uint8List.fromList(source),
          branchName: 'فرع مدينة نصر',
          capturedAt: DateTime(2026, 11, 24, 15, 30),
        );
        final decoded = img.decodeJpg(out)!;
        expect(decoded.width, 600);
        expect(decoded.height, 800);
        // Top of the photo is untouched, bottom strip is dark.
        expect(meanLuma(decoded, 0, 100), greaterThan(0.95));
        expect(meanLuma(decoded, 790, 800), lessThan(0.6));
      });
    });

    testWidgets('applies EXIF rotation before stamping', (tester) async {
      await tester.runAsync(() async {
        // Stored landscape 800x600 with "rotate 90" → seen as portrait 600x800.
        final source = whiteJpeg(800, 600, exifOrientation: 6);
        final out = await PhotoWatermark.stampBytes(
          Uint8List.fromList(source),
          branchName: 'فرع',
          capturedAt: DateTime(2026, 11, 24, 9),
        );
        final decoded = img.decodeJpg(out)!;
        expect(decoded.width, 600);
        expect(decoded.height, 800);
        expect(meanLuma(decoded, 790, 800), lessThan(0.6));
        expect(meanLuma(decoded, 0, 100), greaterThan(0.95));
      });
    });

    testWidgets('works with an empty branch name (date only)', (tester) async {
      await tester.runAsync(() async {
        final out = await PhotoWatermark.stampBytes(
          Uint8List.fromList(whiteJpeg(400, 300)),
          branchName: '  ',
          capturedAt: DateTime(2026, 11, 24, 9),
        );
        final decoded = img.decodeJpg(out)!;
        expect(meanLuma(decoded, 295, 300), lessThan(0.6));
      });
    });

    test('rejects bytes that are not an image', () async {
      expect(
        () => PhotoWatermark.stampBytes(
          Uint8List.fromList([1, 2, 3]),
          branchName: 'x',
          capturedAt: DateTime(2026),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  testWidgets('stampFile writes a new jpg next to the source', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('tas302_');
      addTearDown(() => dir.delete(recursive: true));
      final white = img.Image(width: 200, height: 200);
      img.fill(white, color: img.ColorRgb8(255, 255, 255));
      final src = File('${dir.path}/shot.jpg')..writeAsBytesSync(img.encodeJpg(white));
      final out = await PhotoWatermark.stampFile(
        src,
        branchName: 'فرع',
        capturedAt: DateTime(2026, 11, 24, 9),
      );
      expect(out.path, isNot(src.path));
      expect(out.path, startsWith('${dir.path}/shot_stamped_'));
      expect(out.existsSync(), isTrue);
      expect(src.readAsBytesSync(), img.encodeJpg(white)); // original untouched
    });
  });
}
