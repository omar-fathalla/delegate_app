import 'dart:convert';
import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart'
    if (dart.library.io) 'file_download_helper_io.dart';

abstract class FileDownloadHelper {
  static Future<void> downloadBytes({
    required List<int> bytes,
    required String fileName,
    String mimeType = 'text/csv;charset=utf-8',
    String? shareText,
  }) =>
      downloadFileImpl(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        shareText: shareText,
      );

  static Future<void> downloadString({
    required String content,
    required String fileName,
    String mimeType = 'text/csv;charset=utf-8',
    String? shareText,
  }) {
    final bytes = utf8.encode(content);
    return downloadBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      shareText: shareText,
    );
  }
}
