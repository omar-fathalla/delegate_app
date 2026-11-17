// WARNING: Do not run this script until it is updated to the official ت logo.
// It still draws the old white "E" mark and would overwrite App Store, Play,
// iOS AppIcon, and Android launcher icons. logo.png and tashil_splash.png are
// also written here; those in-app assets were left unchanged on purpose.

// ignore_for_file: unnecessary_import, depend_on_referenced_packages, avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Permanent utility script to generate all store and launcher icons
/// for Tashil Employee (`Tashil Employee` / `تساهيل إمبلوي`).
///
/// Usage: flutter test tool/generate_app_icons.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate full icon suite for Tashil Employee', () async {
    final sfFile = File('/System/Library/Fonts/SFNS.ttf');
    final sfLoader = FontLoader('SFNS');
    sfLoader.addFont(Future.value(ByteData.view(sfFile.readAsBytesSync().buffer)));
    await sfLoader.load();

    const m3Purple = Color(0xFF6750A4);
    const white = Colors.white;

    // 1. Render Master Icon (1024x1024)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1024, 1024));
    canvas.drawColor(m3Purple, BlendMode.src);

    final tp = TextPainter(
      text: const TextSpan(
        text: 'E',
        style: TextStyle(
          fontFamily: 'SFNS',
          fontWeight: FontWeight.w900,
          fontSize: 580,
          color: white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dx = (1024 - tp.width) / 2;
    final dy = (1024 - tp.height) / 2 + 20;
    tp.paint(canvas, Offset(dx, dy));

    final picture = recorder.endRecording();
    final uiImg = await picture.toImage(1024, 1024);
    final rawByteData = await uiImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    final primaryImg1024 = img.Image.fromBytes(
      width: 1024,
      height: 1024,
      bytes: rawByteData!.buffer.asUint8List().buffer,
      order: img.ChannelOrder.rgba,
    );

    final storeDir = Directory('assets/store_icons');
    if (!storeDir.existsSync()) storeDir.createSync(recursive: true);

    // App Store 1024x1024 (24-bit RGB, No Alpha)
    final appStoreRgb = img.Image(width: 1024, height: 1024, numChannels: 3);
    for (int y = 0; y < 1024; y++) {
      for (int x = 0; x < 1024; x++) {
        final p = primaryImg1024.getPixel(x, y);
        appStoreRgb.setPixelRgb(x, y, p.r, p.g, p.b);
      }
    }
    File('${storeDir.path}/app_store_1024x1024.png').writeAsBytesSync(img.encodePng(appStoreRgb));

    // Google Play 512x512
    final googlePlayImg = img.copyResize(primaryImg1024, width: 512, height: 512, interpolation: img.Interpolation.cubic);
    File('${storeDir.path}/google_play_512x512.png').writeAsBytesSync(img.encodePng(googlePlayImg));

    // iOS Squircle Preview
    final squircleRec = ui.PictureRecorder();
    final squircleCanvas = Canvas(squircleRec, const Rect.fromLTWH(0, 0, 1024, 1024));
    final rrect = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(225));
    squircleCanvas.clipRRect(rrect);
    squircleCanvas.drawImage(uiImg, Offset.zero, Paint());
    final sqUiImg = await squircleRec.endRecording().toImage(1024, 1024);
    final sqData = await sqUiImg.toByteData(format: ui.ImageByteFormat.png);
    File('${storeDir.path}/tashil_employee_ios_squircle.png').writeAsBytesSync(sqData!.buffer.asUint8List());

    // Update In-App Assets
    File('assets/images/logo.png').writeAsBytesSync(img.encodePng(googlePlayImg));
    final splashImg = img.copyResize(primaryImg1024, width: 800, height: 800, interpolation: img.Interpolation.cubic);
    File('assets/images/splash_logo_light.png').writeAsBytesSync(img.encodePng(splashImg));
    File('assets/images/splash_logo_dark.png').writeAsBytesSync(img.encodePng(splashImg));
    File('assets/images/tashil_splash.png').writeAsBytesSync(img.encodePng(splashImg));

    // Update iOS Runner Assets
    final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    if (iosDir.existsSync()) {
      final sizes = <String, int>{
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-50x50@1x.png': 50,
        'Icon-App-50x50@2x.png': 100,
        'Icon-App-57x57@1x.png': 57,
        'Icon-App-57x57@2x.png': 114,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-72x72@1x.png': 72,
        'Icon-App-72x72@2x.png': 144,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
      };

      for (final entry in sizes.entries) {
        final resized = entry.value == 1024
            ? primaryImg1024
            : img.copyResize(primaryImg1024, width: entry.value, height: entry.value, interpolation: img.Interpolation.cubic);
        File('${iosDir.path}/${entry.key}').writeAsBytesSync(img.encodePng(resized));
      }
    }

    // Render Android Adaptive Foreground (432x432 with transparent background, E sized for 66dp safe zone)
    final fgRec = ui.PictureRecorder();
    final fgCanvas = Canvas(fgRec, const Rect.fromLTWH(0, 0, 432, 432));
    final fgTp = TextPainter(
      text: const TextSpan(
        text: 'E',
        style: TextStyle(
          fontFamily: 'SFNS',
          fontWeight: FontWeight.w900,
          fontSize: 176,
          color: white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fgTp.paint(fgCanvas, Offset((432 - fgTp.width) / 2, (432 - fgTp.height) / 2 + 6));
    final fgUiImg = await fgRec.endRecording().toImage(432, 432);
    final fgBytes = await fgUiImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    final fgImg432 = img.Image.fromBytes(
      width: 432,
      height: 432,
      bytes: fgBytes!.buffer.asUint8List().buffer,
      order: img.ChannelOrder.rgba,
    );

    // Update Android mipmaps & adaptive icon foregrounds
    final androidMipmaps = <String, int>{
      'android/app/src/main/res/mipmap-mdpi': 48,
      'android/app/src/main/res/mipmap-hdpi': 72,
      'android/app/src/main/res/mipmap-xhdpi': 96,
      'android/app/src/main/res/mipmap-xxhdpi': 144,
      'android/app/src/main/res/mipmap-xxxhdpi': 192,
    };
    final adaptiveForegroundSizes = <String, int>{
      'android/app/src/main/res/mipmap-mdpi': 108,
      'android/app/src/main/res/mipmap-hdpi': 162,
      'android/app/src/main/res/mipmap-xhdpi': 216,
      'android/app/src/main/res/mipmap-xxhdpi': 324,
      'android/app/src/main/res/mipmap-xxxhdpi': 432,
    };
    for (final entry in androidMipmaps.entries) {
      final dir = Directory(entry.key);
      if (dir.existsSync()) {
        final resized = img.copyResize(primaryImg1024, width: entry.value, height: entry.value, interpolation: img.Interpolation.cubic);
        File('${dir.path}/launcher_icon.png').writeAsBytesSync(img.encodePng(resized));
        File('${dir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(resized));
        final roundResized = img.copyCropCircle(resized);
        File('${dir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(roundResized));

        final fgSize = adaptiveForegroundSizes[entry.key]!;
        final fgResized = fgSize == 432
            ? fgImg432
            : img.copyResize(fgImg432, width: fgSize, height: fgSize, interpolation: img.Interpolation.cubic);
        File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(fgResized));
      }
    }

    // Write Android Adaptive Icon XMLs
    final anyDpiDir = Directory('android/app/src/main/res/mipmap-anydpi-v26');
    if (!anyDpiDir.existsSync()) anyDpiDir.createSync(recursive: true);
    const adaptiveXml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''';
    File('${anyDpiDir.path}/launcher_icon.xml').writeAsBytesSync(adaptiveXml.codeUnits);
    File('${anyDpiDir.path}/ic_launcher.xml').writeAsBytesSync(adaptiveXml.codeUnits);
    File('${anyDpiDir.path}/ic_launcher_round.xml').writeAsBytesSync(adaptiveXml.codeUnits);

    final colorsFile = File('android/app/src/main/res/values/ic_launcher_background.xml');
    colorsFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#6750A4</color>
</resources>
''');

    print('Icon generation complete!');
  });
}
