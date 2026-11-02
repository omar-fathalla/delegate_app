import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Result of a finished task image upload.
class TaskImageUpload {
  final String url;
  final String path;
  const TaskImageUpload({required this.url, required this.path});
}

/// Uploads the image a sender attaches to a task.
///
/// Files live at `organizations/{orgId}/task_images/{uploaderUid}/{uuid}.jpg`
/// so the Storage rules can tie every file to the uid that uploaded it.
class TaskImageStorage {
  TaskImageStorage({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage,
      _auth = auth;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  static const int maxBytes = 5 * 1024 * 1024;

  static String pathFor(String orgId, String uploaderUid, String fileId) =>
      'organizations/$orgId/task_images/$uploaderUid/$fileId.jpg';

  /// Starts the upload. [onProgress] receives 0..1.
  Future<TaskImageUpload> upload({
    required String organizationId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) throw StateError('not-signed-in');
    final path = pathFor(organizationId, uid, const Uuid().v4());
    final ref = (_storage ?? FirebaseStorage.instance).ref(path);
    final task = ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    final url = await ref.getDownloadURL();
    return TaskImageUpload(url: url, path: path);
  }
}
