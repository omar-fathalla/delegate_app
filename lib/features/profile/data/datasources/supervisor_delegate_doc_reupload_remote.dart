import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/admin/data/datasources/storage_upload_intent.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';

/// Signed-in delegate id (TAS-28: delegateId claim, else the Auth uid), or
/// null when Firebase is not initialised (unit tests).
String? _currentUid() => DelegateIdentity.current();

/// TAS-72: Storage already lets the signed-in user write its own
/// `delegate_documents/<uid>/` folder (`request.auth.uid == folderId`).
/// `ensureStorageUploadIntent` is staff-only and answers `caller_not_staff`
/// for a delegate, so it is only called when the caller does not own the
/// folder (a supervisor uploading for a delegate).
bool callerOwnsDocumentFolder(String folderId, {String? callerUid}) {
  final uid = (callerUid ?? _currentUid())?.trim() ?? '';
  return uid.isNotEmpty && uid == folderId.trim();
}

/// TAS-72 (a), decided by the user 2026-11-22: which `delegate_documents/`
/// folder a document re-upload for [profileUid] goes to.
///
/// A delegate signs in once (one auth uid) but can hold profiles in several
/// companies; its token lists them in `delegateIds`. Storage only lets the
/// caller write `delegate_documents/<auth.uid>/`, so when a delegate edits a
/// *secondary* profile the file goes to the caller's own folder: it is the
/// same person and the same ID card. The Firestore rules only check that the
/// stored URL matches the pending `documents` entry, not the folder.
/// Anyone else (staff uploading for a delegate) keeps [profileUid].
String chooseDelegateDocumentFolder({
  required String profileUid,
  required String callerUid,
  required String callerRole,
  required List<String> callerDelegateIds,
}) {
  final caller = callerUid.trim();
  final profile = profileUid.trim();
  if (caller.isEmpty || caller == profile) return profile;
  if (callerRole.trim().toLowerCase() == 'delegate' &&
      callerDelegateIds.map((e) => e.trim()).contains(profile)) {
    return caller;
  }
  return profile;
}

/// Reads the signed-in user's uid and token claims and applies
/// [chooseDelegateDocumentFolder]. Falls back to [profileUid] on any error.
Future<String> resolveDelegateDocumentFolder(String profileUid) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == profileUid) return profileUid;
    final claims = (await user.getIdTokenResult()).claims ?? const {};
    final ids = claims['delegateIds'];
    // TAS-28: the caller's own folder is its delegate id (claim).
    final me = DelegateIdentity.fromClaims(uid: user.uid, claims: claims) ?? user.uid;
    if (me == profileUid) return profileUid;
    return chooseDelegateDocumentFolder(
      profileUid: profileUid,
      callerUid: me,
      callerRole: (claims['role'] ?? '').toString(),
      callerDelegateIds: ids is List ? ids.map((e) => e.toString()).toList() : const [],
    );
  } catch (_) {
    return profileUid;
  }
}

class SupervisorDocReuploadException implements Exception {
  SupervisorDocReuploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// User-facing message for profile document replace failures (intent / Storage / callable).
String supervisorDocReplaceErrorMessage(Object error) {
  if (error is SupervisorDocReuploadException) return error.message;
  if (error is FirebaseException && error.plugin == 'firebase_storage') {
    switch (error.code) {
      case 'unauthorized':
        return 'تعذر رفع المستند: صلاحية التخزين مرفوضة. '
            'تأكد من تسجيل الدخول ثم أعد المحاولة.';
      case 'canceled':
        return 'تم إلغاء رفع المستند.';
      case 'retry-limit-exceeded':
        return 'تعذر رفع المستند بعد عدة محاولات. تحقق من الاتصال وأعد المحاولة.';
      case 'unknown':
        return 'تعذر رفع المستند إلى التخزين. أعد المحاولة.';
      default:
        return 'تعذر رفع المستند (${error.code}). أعد المحاولة.';
    }
  }
  if (error is FirebaseFunctionsException) {
    final raw = error.message?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return 'تعذر تحديث المستند على الخادم. حاول مرة أخرى.';
  }
  final text = error.toString().replaceAll('Exception: ', '').trim();
  if (text.isNotEmpty && text != error.runtimeType.toString()) {
    return text;
  }
  return 'فشل تحديث المستند. حاول مرة أخرى.';
}

/// Storage path for a supervisor/delegate document JPEG under [delegateUid].
String delegateDocumentStoragePath({
  required String delegateUid,
  required String docType,
  int? timestampMs,
}) {
  final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  return 'delegate_documents/$delegateUid/${docType}_$ts.jpg';
}

/// Ensures upload intent, then writes [file] to [storagePath]. Used before
/// client Firestore merges and before [SupervisorDelegateDocReuploadRemote.reupload].
Future<String> uploadDelegateDocumentFile({
  required String folderId,
  required String companyUID,
  required String storagePath,
  required File file,
  FirebaseFunctions? functions,
  FirebaseStorage? storage,
  Future<String?> Function({
    required String folderId,
    required String companyUID,
    FirebaseFunctions? functions,
  })? ensureIntent,
  String? callerUid,
}) async {
  if (!callerOwnsDocumentFolder(folderId, callerUid: callerUid)) {
    final intentError = await (ensureIntent ?? _defaultEnsureIntent)(
      folderId: folderId,
      companyUID: companyUID,
      functions: functions,
    );
    if (intentError != null) {
      throw SupervisorDocReuploadException(intentError);
    }
  }
  try {
    final ref = (storage ?? FirebaseStorage.instance).ref(storagePath);
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  } on FirebaseException catch (e) {
    throw SupervisorDocReuploadException(storageUploadErrorMessage(e));
  }
}

String storageUploadErrorMessage(FirebaseException e) {
  if (e.plugin != 'firebase_storage') {
    return supervisorDocReplaceErrorMessage(e);
  }
  switch (e.code) {
    case 'unauthorized':
      return 'تعذر رفع المستند: صلاحية التخزين مرفوضة. '
          'تأكد من تسجيل الدخول ثم أعد المحاولة.';
    case 'canceled':
      return 'تم إلغاء رفع المستند.';
    case 'retry-limit-exceeded':
      return 'تعذر رفع المستند بعد عدة محاولات. تحقق من الاتصال وأعد المحاولة.';
    default:
      return 'تعذر رفع المستند (${e.code}). أعد المحاولة.';
  }
}

Future<String> _uploadAfterIntent({
  required String folderId,
  required String companyUID,
  required String path,
  required File file,
  required Future<String> Function(String path, File file) uploadFile,
  Future<String?> Function({
    required String folderId,
    required String companyUID,
    FirebaseFunctions? functions,
  })? ensureIntent,
}) async {
  final intentError = await (ensureIntent ?? _defaultEnsureIntent)(
    folderId: folderId,
    companyUID: companyUID,
  );
  if (intentError != null) {
    throw SupervisorDocReuploadException(intentError);
  }
  return uploadFile(path, file);
}

Future<String?> _defaultEnsureIntent({
  required String folderId,
  required String companyUID,
  FirebaseFunctions? functions,
}) =>
    ensureStorageUploadIntent(
      folderId: folderId,
      companyUID: companyUID,
      functions: functions,
    );

/// Server-side supervisor active→pending document replace (Mohamed 2026-11-15).
class SupervisorDelegateDocReuploadRemote {
  SupervisorDelegateDocReuploadRemote({
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  })  : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _storage = storage;

  final FirebaseFunctions _functions;
  final FirebaseStorage? _storage;

  Future<void> reupload({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String docType,
    required String newUrl,
  }) async {
    try {
      await _functions.httpsCallable('supervisorReuploadDelegateDocument').call({
        'uid': uid,
        'organizationUID': organizationUID,
        'companyUID': companyUID,
        'docType': docType,
        'newUrl': newUrl,
      });
    } on FirebaseFunctionsException catch (e) {
      throw SupervisorDocReuploadException(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'تعذر تحديث المستند على الخادم. حاول مرة أخرى.',
      );
    } catch (_) {
      throw SupervisorDocReuploadException(
        'تعذر تحديث المستند على الخادم. حاول مرة أخرى.',
      );
    }
  }

  /// Intent → Storage upload → supervisor callable (active→pending doc replace).
  Future<void> replaceWithFile({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String docType,
    required File file,
    Future<String?> Function({
      required String folderId,
      required String companyUID,
      FirebaseFunctions? functions,
    })? ensureIntent,
    Future<String> Function(String path, File file)? uploadFile,
  }) async {
    final path = delegateDocumentStoragePath(delegateUid: uid, docType: docType);
    final newUrl = uploadFile != null
        ? await _uploadAfterIntent(
            folderId: uid,
            companyUID: companyUID,
            path: path,
            file: file,
            ensureIntent: ensureIntent,
            uploadFile: uploadFile,
          )
        : await uploadDelegateDocumentFile(
            folderId: uid,
            companyUID: companyUID,
            storagePath: path,
            file: file,
            functions: _functions,
            storage: _storage,
            ensureIntent: ensureIntent,
          );
    await reupload(
      uid: uid,
      organizationUID: organizationUID,
      companyUID: companyUID,
      docType: docType,
      newUrl: newUrl,
    );
  }
}

/// Server-side SA / technical support approved document replace.
class PrivilegedDelegateDocReuploadRemote {
  PrivilegedDelegateDocReuploadRemote({
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  })  : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _storage = storage;

  final FirebaseFunctions _functions;
  final FirebaseStorage? _storage;

  Future<void> reviewDocument({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String docType,
    required bool approve,
    String? rejectionReason,
  }) async {
    try {
      await _functions.httpsCallable('privilegedReuploadDelegateDocument').call({
        'uid': uid,
        'organizationUID': organizationUID,
        'companyUID': companyUID,
        'docType': docType,
        'approve': approve,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      });
    } on FirebaseFunctionsException catch (e) {
      throw SupervisorDocReuploadException(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'تعذر تحديث حالة المستند على الخادم. حاول مرة أخرى.',
      );
    } catch (_) {
      throw SupervisorDocReuploadException(
        'تعذر تحديث حالة المستند على الخادم. حاول مرة أخرى.',
      );
    }
  }

  Future<void> reupload({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String docType,
    required String newUrl,
  }) async {
    try {
      await _functions.httpsCallable('privilegedReuploadDelegateDocument').call({
        'uid': uid,
        'organizationUID': organizationUID,
        'companyUID': companyUID,
        'docType': docType,
        'newUrl': newUrl,
      });
    } on FirebaseFunctionsException catch (e) {
      throw SupervisorDocReuploadException(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'تعذر تحديث المستند على الخادم. حاول مرة أخرى.',
      );
    } catch (_) {
      throw SupervisorDocReuploadException(
        'تعذر تحديث المستند على الخادم. حاول مرة أخرى.',
      );
    }
  }

  Future<void> replaceWithFile({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String docType,
    required File file,
    Future<String?> Function({
      required String folderId,
      required String companyUID,
      FirebaseFunctions? functions,
    })? ensureIntent,
    Future<String> Function(String path, File file)? uploadFile,
  }) async {
    final path = delegateDocumentStoragePath(delegateUid: uid, docType: docType);
    final newUrl = uploadFile != null
        ? await _uploadAfterIntent(
            folderId: uid,
            companyUID: companyUID,
            path: path,
            file: file,
            ensureIntent: ensureIntent,
            uploadFile: uploadFile,
          )
        : await uploadDelegateDocumentFile(
            folderId: uid,
            companyUID: companyUID,
            storagePath: path,
            file: file,
            functions: _functions,
            storage: _storage,
            ensureIntent: ensureIntent,
          );
    await reupload(
      uid: uid,
      organizationUID: organizationUID,
      companyUID: companyUID,
      docType: docType,
      newUrl: newUrl,
    );
  }
}