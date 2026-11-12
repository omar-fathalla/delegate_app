import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/admin/data/datasources/storage_upload_intent.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Result of a finished task image upload.
///
/// [url] is left empty on new uploads: display goes through
/// [TaskImageFetcher] so a public download URL is never stored or shown.
class TaskImageUpload {
  final String url;
  final String path;
  const TaskImageUpload({required this.url, required this.path});
}

/// Uploads the image a sender attaches to a task.
///
/// New files live at
/// `task_images/{companyId}/{uploaderUid}/task_{uid}_{token}.jpg`
/// after [ensureStorageUploadIntent] reserves the object name. Ownership
/// is the exact N1-r filename (a shorter uid cannot claim
/// `task_{uid}_2_*`).
class TaskImageStorage {
  TaskImageStorage({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    Future<String?> Function({
      required String folderId,
      required String companyUID,
      String? purpose,
      FirebaseFunctions? functions,
    })?
    ensureIntent,
  }) : _storage = storage,
       _auth = auth,
       _functions = functions,
       _ensureIntent = ensureIntent;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;
  final FirebaseFunctions? _functions;
  final Future<String?> Function({
    required String folderId,
    required String companyUID,
    String? purpose,
    FirebaseFunctions? functions,
  })?
  _ensureIntent;

  static const int maxBytes = 5 * 1024 * 1024;

  static String fileNameFor(String uploaderUid, String token) =>
      'task_${uploaderUid}_$token.jpg';

  static String pathFor(String companyId, String uploaderUid, String token) =>
      'task_images/$companyId/$uploaderUid/${fileNameFor(uploaderUid, token)}';

  /// Starts the upload. [onProgress] receives 0..1.
  Future<TaskImageUpload> upload({
    required String companyId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) throw StateError('not-signed-in');
    final company = companyId.trim();
    if (company.isEmpty) throw StateError('company_required');
    final token = DateTime.now().millisecondsSinceEpoch.toString();
    if (token.contains('_')) throw StateError('invalid-token');
    final name = fileNameFor(uid, token);
    final path = pathFor(company, uid, token);
    final intentError = await (_ensureIntent ?? ensureStorageUploadIntent)(
      folderId: name,
      companyUID: company,
      purpose: 'task_image',
      functions: _functions,
    );
    if (intentError != null) {
      throw StateError(intentError);
    }
    final ref = (_storage ?? FirebaseStorage.instance).ref(path);
    final task = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return TaskImageUpload(url: '', path: path);
  }

  Future<void> deleteQuietly(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    try {
      await (_storage ?? FirebaseStorage.instance).ref(trimmed).delete();
    } catch (_) {}
  }
}

/// Loads task-image bytes through the [getTaskImage] callable.
class TaskImageFetcher {
  TaskImageFetcher({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  /// Test/preview seam used by the thumbnail widget.
  @visibleForTesting
  static TaskImageFetcher? debugOverride;

  /// True when the caller can see the task but is not a grant reader.
  static bool isAccessDenied(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('not_allowed')) {
      return true;
    }
    try {
      final code = (error as dynamic).code?.toString().toLowerCase();
      if (code == 'permission-denied' || code == 'permission_denied') {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Uint8List> load({
    required String imagePath,
    String? taskId,
    String? organizationId,
  }) async {
    final path = imagePath.trim();
    if (path.isEmpty) {
      throw StateError('image_path_required');
    }
    final callable =
        (_functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'))
            .httpsCallable('getTaskImage');
    final result = await callable.call({
      'imagePath': path,
      if (taskId != null && taskId.trim().isNotEmpty) 'taskId': taskId.trim(),
      if (organizationId != null && organizationId.trim().isNotEmpty)
        'organizationId': organizationId.trim(),
    });
    final data = result.data;
    if (data is! Map) throw StateError('invalid_image_response');
    final encoded = data['data']?.toString() ?? '';
    if (encoded.isEmpty) throw StateError('invalid_image_response');
    return Uint8List.fromList(base64Decode(encoded));
  }
}
