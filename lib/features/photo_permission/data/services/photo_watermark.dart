import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// TAS-302: burns the branch name and the capture date/time into a field
/// photo, as a dark strip along the bottom edge.
///
/// The stamp is part of the JPEG pixels, so every place that shows, downloads
/// or shares the uploaded file carries it, with no change on the viewer side.
///
/// Arabic text is laid out by Flutter's [TextPainter] (the `image` package
/// fonts are bitmap Latin only); decoding, compositing and JPEG encoding run
/// in a background isolate through the `image` package.
class PhotoWatermark {
  PhotoWatermark._();

  /// JPEG quality of the stamped file. The picker already compressed the
  /// photo (quality 50, max 1080px), so this keeps the size close to it.
  static const int jpegQuality = 80;

  /// `24/11/2026  3:05 م` for a Cairo wall-clock [time].
  static String formatStamp(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = time.hour < 12 ? 'ص' : 'م';
    return '${two(time.day)}/${two(time.month)}/${time.year}  '
        '$hour12:${two(time.minute)} $period';
  }

  /// Stamps [source] and writes the result next to it as `<name>_stamped.jpg`.
  static Future<File> stampFile(
    File source, {
    required String branchName,
    required DateTime capturedAt,
  }) async {
    final bytes = await source.readAsBytes();
    final stamped = await stampBytes(
      bytes,
      branchName: branchName,
      capturedAt: capturedAt,
    );
    final path = source.path;
    final dot = path.lastIndexOf('.');
    final base = dot > path.lastIndexOf(Platform.pathSeparator)
        ? path.substring(0, dot)
        : path;
    final out = File('${base}_stamped_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await out.writeAsBytes(stamped, flush: true);
    return out;
  }

  /// Returns JPEG bytes of [source] with the stamp drawn on it.
  ///
  /// [capturedAt] is shown as is (pass Cairo wall-clock time).
  static Future<Uint8List> stampBytes(
    Uint8List source, {
    required String branchName,
    required DateTime capturedAt,
  }) async {
    final photo = await compute(_decodeUpright, source);
    final strip = await _renderStrip(
      width: photo.width,
      branchName: branchName.trim(),
      stamp: formatStamp(capturedAt),
    );
    return compute(_composeAndEncode, _ComposeJob(photo, strip, jpegQuality));
  }

  static Future<img.Image> _renderStrip({
    required int width,
    required String branchName,
    required String stamp,
  }) async {
    final fontSize = (width * 0.036).clamp(14.0, 64.0);
    final padding = fontSize * 0.7;
    final maxTextWidth = width - padding * 2;
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];

    TextPainter painter(String text, FontWeight weight, double size) {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontFamily: 'Cairo', // bundled app font: same look on every phone
            fontSize: size,
            fontWeight: weight,
            height: 1.25,
            shadows: shadow,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxTextWidth);
    }

    final lines = <TextPainter>[
      if (branchName.isNotEmpty) painter(branchName, FontWeight.w700, fontSize),
      painter(stamp, FontWeight.w500, fontSize * 0.9),
    ];
    final gap = fontSize * 0.25;
    final textHeight = lines.fold<double>(0, (h, p) => h + p.height) +
        gap * (lines.length - 1);
    final height = (textHeight + padding * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0x8C000000),
    );
    var y = padding;
    for (final line in lines) {
      line.paint(canvas, Offset(width - padding - line.width, y));
      y += line.height + gap;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) {
        throw StateError('watermark strip could not be rasterised');
      }
      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } finally {
      image.dispose();
    }
  }
}

/// Decodes the photo and applies its EXIF orientation, so the strip lands on
/// the bottom of the picture as the user sees it.
img.Image _decodeUpright(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null; // some format sniffers throw on truncated input
  }
  if (decoded == null) {
    throw const FormatException('unsupported photo format');
  }
  return img.bakeOrientation(decoded);
}

class _ComposeJob {
  final img.Image photo;
  final img.Image strip;
  final int quality;
  const _ComposeJob(this.photo, this.strip, this.quality);
}

Uint8List _composeAndEncode(_ComposeJob job) {
  final photo = job.photo.numChannels == 3
      ? job.photo
      : job.photo.convert(numChannels: 3);
  img.compositeImage(
    photo,
    job.strip,
    dstX: 0,
    dstY: photo.height - job.strip.height,
  );
  return img.encodeJpg(photo, quality: job.quality);
}
