// ignore_for_file: unnecessary_import, depend_on_referenced_packages, avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Generates store and launcher icons for Tashil Employee.
///
/// Official mark: brand purple #6750A4 full background, centered
/// #EADDFF tile (radius 29% of the tile, 68% of the canvas — measured
/// from the approved circle-crop reference), Cairo ExtraBold ت in
/// #21005D. Usage: `flutter test tool/generate_app_icons.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate full icon suite for Tashil Employee', () async {
    const brandPurple = Color(0xFF6750A4);
    const tileColor = Color(0xFFEADDFF);
    const glyphColor = Color(0xFF21005D);
    // Tile side / canvas, from Mohamed's 300px circle-crop reference (204/300).
    const tileRatio = 204 / 300;
    // Adaptive mask is the center 72dp of the 108dp foreground.
    const adaptiveMask = 72 / 108;

    final fontFile = File('assets/fonts/Cairo/Cairo-ExtraBold.ttf');
    expect(fontFile.existsSync(), isTrue, reason: 'Cairo ExtraBold must be in assets/fonts/Cairo');
    final cairoLoader = FontLoader('CairoExtraBold');
    cairoLoader.addFont(
      Future.value(ByteData.view(fontFile.readAsBytesSync().buffer)),
    );
    await cairoLoader.load();

    Future<ui.Image> paintLogo({
      required double canvasSize,
      required double tileRatioOnCanvas,
      required bool transparentBackground,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasSize, canvasSize));
      if (transparentBackground) {
        canvas.drawColor(const Color(0x00000000), BlendMode.src);
      } else {
        canvas.drawColor(brandPurple, BlendMode.src);
      }

      final tileSize = canvasSize * tileRatioOnCanvas;
      final origin = (canvasSize - tileSize) / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(origin, origin, tileSize, tileSize),
        Radius.circular(tileSize * 0.29),
      );
      canvas.drawRRect(rrect, Paint()..color = tileColor);

      final tp = TextPainter(
        text: TextSpan(
          text: 'ت',
          style: TextStyle(
            fontFamily: 'CairoExtraBold',
            fontWeight: FontWeight.w800,
            fontSize: tileSize * 0.5,
            height: 1.2,
            color: glyphColor,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          origin + (tileSize - tp.width) / 2,
          origin + (tileSize - tp.height) / 2,
        ),
      );

      return recorder.endRecording().toImage(canvasSize.toInt(), canvasSize.toInt());
    }

    Future<img.Image> toImg(ui.Image uiImg) async {
      final raw = await uiImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      return img.Image.fromBytes(
        width: uiImg.width,
        height: uiImg.height,
        bytes: raw!.buffer.asUint8List().buffer,
        order: img.ChannelOrder.rgba,
      );
    }

    img.Image asRgb(img.Image src) {
      final out = img.Image(width: src.width, height: src.height, numChannels: 3);
      for (int y = 0; y < src.height; y++) {
        for (int x = 0; x < src.width; x++) {
          final p = src.getPixel(x, y);
          out.setPixelRgb(x, y, p.r, p.g, p.b);
        }
      }
      return out;
    }

    final uiImg = await paintLogo(
      canvasSize: 1024,
      tileRatioOnCanvas: tileRatio,
      transparentBackground: false,
    );
    final primaryImg1024 = await toImg(uiImg);
    final appStoreRgb = asRgb(primaryImg1024);

    final storeDir = Directory('assets/store_icons');
    if (!storeDir.existsSync()) storeDir.createSync(recursive: true);

    File('${storeDir.path}/app_store_1024x1024.png')
        .writeAsBytesSync(img.encodePng(appStoreRgb));

    final googlePlayImg = img.copyResize(
      primaryImg1024,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.cubic,
    );
    File('${storeDir.path}/google_play_512x512.png')
        .writeAsBytesSync(img.encodePng(googlePlayImg));

    final squircleRec = ui.PictureRecorder();
    final squircleCanvas = Canvas(squircleRec, const Rect.fromLTWH(0, 0, 1024, 1024));
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 1024, 1024),
      const Radius.circular(225),
    );
    squircleCanvas.clipRRect(rrect);
    squircleCanvas.drawImage(uiImg, Offset.zero, Paint());
    final sqUiImg = await squircleRec.endRecording().toImage(1024, 1024);
    final sqData = await sqUiImg.toByteData(format: ui.ImageByteFormat.png);
    File('${storeDir.path}/tashil_employee_ios_squircle.png')
        .writeAsBytesSync(sqData!.buffer.asUint8List());
    File('${storeDir.path}/ios_squircle_preview_1024.png')
        .writeAsBytesSync(sqData.buffer.asUint8List());

    // In-app logo and splash (same on-purple mark; splash keeps #6750A4).
    File('assets/images/logo.png').writeAsBytesSync(img.encodePng(googlePlayImg));
    final splashImg = img.copyResize(
      primaryImg1024,
      width: 800,
      height: 800,
      interpolation: img.Interpolation.cubic,
    );
    File('assets/images/splash_logo_light.png').writeAsBytesSync(img.encodePng(splashImg));
    File('assets/images/splash_logo_dark.png').writeAsBytesSync(img.encodePng(splashImg));
    File('assets/images/tashil_splash.png').writeAsBytesSync(img.encodePng(splashImg));

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
            ? appStoreRgb
            : img.copyResize(
                primaryImg1024,
                width: entry.value,
                height: entry.value,
                interpolation: img.Interpolation.cubic,
              );
        final bytes = entry.value == 1024 ? img.encodePng(appStoreRgb) : img.encodePng(asRgb(resized));
        File('${iosDir.path}/${entry.key}').writeAsBytesSync(bytes);
      }
    }

    final fgUiImg = await paintLogo(
      canvasSize: 432,
      tileRatioOnCanvas: tileRatio * adaptiveMask,
      transparentBackground: true,
    );
    final fgImg432 = await toImg(fgUiImg);

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
        final resized = img.copyResize(
          primaryImg1024,
          width: entry.value,
          height: entry.value,
          interpolation: img.Interpolation.cubic,
        );
        File('${dir.path}/launcher_icon.png').writeAsBytesSync(img.encodePng(resized));
        File('${dir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(resized));
        final roundResized = img.copyCropCircle(resized);
        File('${dir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(roundResized));

        final fgSize = adaptiveForegroundSizes[entry.key]!;
        final fgResized = fgSize == 432
            ? fgImg432
            : img.copyResize(
                fgImg432,
                width: fgSize,
                height: fgSize,
                interpolation: img.Interpolation.cubic,
              );
        File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(fgResized));
      }
    }

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

    File('android/app/src/main/res/values/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#6750A4</color>
</resources>
''');

    print('Icon generation complete!');
  });
}
