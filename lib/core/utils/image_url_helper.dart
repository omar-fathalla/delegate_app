import 'package:flutter/foundation.dart';

/// Helper utility for normalizing and resolving image URLs safely across platforms (Web & Mobile).
/// On Flutter Web (CanvasKit / WebGL), cross-origin requests to Google Cloud Storage or Firebase Storage
/// are blocked by browser CORS restrictions if the bucket lacks wildcard CORS headers.
/// This utility routes URLs through an edge-cached CORS proxy (wsrv.nl) with Access-Control-Allow-Origin: *
/// when running on the web, while preserving native socket loading on mobile.
class ImageUrlHelper {
  ImageUrlHelper._();

  /// Returns a web-safe image URL.
  /// On Web: encodes and routes Firebase/GCS storage URLs through wsrv.nl proxy with optional dimensions.
  /// On Native (iOS/Android/Desktop): returns the original URL untouched.
  static String getWebSafeUrl(
    String? originalUrl, {
    int? width,
    int? height,
  }) {
    if (originalUrl == null) return '';
    final trimmed = originalUrl.trim();
    if (trimmed.isEmpty) return '';

    // Non-web platforms use native network sockets without browser CORS restrictions
    if (!kIsWeb) {
      return trimmed;
    }

    // Only HTTP/HTTPS URLs need proxying
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return trimmed;
    }

    // Already routed through wsrv.nl or a CORS-friendly proxy
    if (trimmed.startsWith('https://wsrv.nl/?url=')) {
      return trimmed;
    }

    // Proxy Firebase Storage and Google Cloud Storage URLs to guarantee CORS headers
    final isStorageUrl = trimmed.contains('firebasestorage.googleapis.com') ||
        trimmed.contains('storage.googleapis.com') ||
        trimmed.contains('firebasestorage.app');

    if (isStorageUrl) {
      final encoded = Uri.encodeComponent(trimmed);
      final buffer = StringBuffer('https://wsrv.nl/?url=$encoded');
      if (width != null && width > 0) {
        buffer.write('&w=$width');
      }
      if (height != null && height > 0) {
        buffer.write('&h=$height');
      }
      buffer.write('&fit=cover');
      return buffer.toString();
    }

    return trimmed;
  }
}
