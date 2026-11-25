import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/storage_media.dart';

class PhotoCacheManager {
  static const String cacheKey = 'tashil_persistent_photo_cache';

  /// Persistent cache manager keeping images locally on disk for up to 365 days
  static final CacheManager instance = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 3000,
      fileService: HttpFileService(),
    ),
  );

  /// Pre-caches a list of photo URLs in the background into persistent disk cache
  static void precachePhotos(Iterable<String> photoUrls, {int maxBatch = 20}) {
    int count = 0;
    for (final url in photoUrls) {
      if (count >= maxBatch) break;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        instance.downloadFile(url).ignore();
        count++;
      } else if (StorageMediaRef.isStoragePath(url)) {
        // TAS-42: a stored Storage path; resolve through the rules first.
        StorageMediaResolver.instance.tryResolve(url).then((resolved) {
          if (resolved != null) {
            instance.downloadFile(resolved, key: url).ignore();
          }
        }).ignore();
        count++;
      }
    }
  }

  /// A file on disk for a stored photo: a URL (disk cache), a Storage path
  /// (local copy first, then resolved through the rules) or a local path.
  static Future<File?> fileForStoredPhoto(String stored) async {
    if (stored.startsWith('http://') || stored.startsWith('https://')) {
      return instance.getSingleFile(stored);
    }
    final local = await resolveLocalPhotoFile(stored);
    if (local != null && await local.exists()) return local;
    if (StorageMediaRef.isStoragePath(stored)) {
      final url = await StorageMediaResolver.instance.resolve(stored);
      if (url != null) return instance.getSingleFile(url, key: stored);
    }
    return null;
  }

  /// Resolves local image files across iOS/Android sandbox path rotations
  static Future<File?> resolveLocalPhotoFile(String storedPath) async {
    if (storedPath.isEmpty || storedPath.startsWith('http://') || storedPath.startsWith('https://')) {
      return null;
    }

    final directFile = File(storedPath);
    if (await directFile.exists()) {
      return directFile;
    }

    try {
      final name = p.basename(storedPath);
      final appDir = await getApplicationDocumentsDirectory();

      // 1. Check in offline_captured_photos
      final offlineFile = File('${appDir.path}/offline_captured_photos/$name');
      if (await offlineFile.exists()) {
        return offlineFile;
      }

      // 2. Check directly in App Documents Directory
      final docFile = File('${appDir.path}/$name');
      if (await docFile.exists()) {
        return docFile;
      }

      // 3. Check in Temporary Directory
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$name');
      if (await tempFile.exists()) {
        return tempFile;
      }
    } catch (_) {}

    return directFile;
  }

  /// Saves any captured photo (remote URL or local file path) directly to the device Gallery
  static Future<bool> savePhotoToGallery(
    BuildContext context, {
    required String photoUrl,
    String? customName,
  }) async {
    try {
      // 1. Check & request gallery access permission
      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        return false;
      }

      // 2. Obtain local file from cache or disk or direct download
      String filePath;
      if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
        try {
          final file = await instance.getSingleFile(photoUrl);
          filePath = file.path;
        } catch (e) {
          debugPrint('PhotoCacheManager: cache getSingleFile failed ($e), falling back to direct download');
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(photoUrl));
          final response = await request.close();
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_gallery_${DateTime.now().millisecondsSinceEpoch}.jpg');
          final bytes = await consolidateHttpClientResponseBytes(response);
          await tempFile.writeAsBytes(bytes);
          filePath = tempFile.path;
        }
      } else {
        final resolvedFile = await fileForStoredPhoto(photoUrl);
        if (resolvedFile == null || !await resolvedFile.exists()) {
          throw Exception('ملف الصورة غير موجود على الهاتف');
        }
        filePath = resolvedFile.path;
      }

      // 3. Save to phone gallery
      await Gal.putImage(filePath);
      return true;
    } catch (e) {
      debugPrint('PhotoCacheManager savePhotoToGallery Error: $e');
      rethrow;
    }
  }
}
