import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/features/admin/data/datasources/storage_upload_intent.dart';

class DelegateProfileEditException implements Exception {
  DelegateProfileEditException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Strips raw HTTP / callable-code suffixes such as " [409]" from a message.
@visibleForTesting
String stripCallableErrorSuffix(String message) {
  return message.trim().replaceAll(
    RegExp(r'\s*\[(?:\d{3}|[a-z][a-z0-9-]+)\]\s*$', caseSensitive: false),
    '',
  ).trim();
}

@visibleForTesting
String callableErrorMessage(
  FirebaseFunctionsException e, {
  String fallback = 'تعذر إتمام العملية. حاول مرة أخرى.',
}) {
  final message = stripCallableErrorSuffix(e.message ?? '');
  return message.isNotEmpty ? message : fallback;
}

class DelegateProfileSaveResult {
  const DelegateProfileSaveResult({
    required this.saved,
    this.imagesFailed = false,
    this.message,
  });

  final bool saved;
  final bool imagesFailed;
  final String? message;
}

/// Uploads any picked images, then saves profile fields. A failed image
/// upload does not drop name/phone changes from the same save.
@visibleForTesting
Future<DelegateProfileSaveResult> saveDelegateProfileEdit({
  required Future<String> Function({
    required String delegateUid,
    required String kind,
    required XFile file,
  }) upload,
  required Future<void> Function({
    String? fullName,
    String? phoneNumber,
    String? personalPhotoURL,
    String? nationalIdFrontUrl,
    String? nationalIdBackUrl,
  }) edit,
  required String delegateUid,
  String? fullName,
  String? phoneNumber,
  XFile? personalPhoto,
  XFile? idFront,
  XFile? idBack,
}) async {
  String? imageError;
  Future<String?> tryUpload(XFile? file, String kind) async {
    if (file == null) return null;
    try {
      return await upload(delegateUid: delegateUid, kind: kind, file: file);
    } on DelegateProfileEditException catch (e) {
      imageError = e.message;
      return null;
    } catch (_) {
      imageError = 'تعذر رفع الصور. حاول مرة أخرى.';
      return null;
    }
  }

  final photoUrl = await tryUpload(personalPhoto, 'profile');
  final frontUrl = await tryUpload(idFront, 'national_id_front');
  final backUrl = await tryUpload(idBack, 'national_id_back');

  final hasText = (fullName != null && fullName.isNotEmpty) ||
      (phoneNumber != null && phoneNumber.isNotEmpty);
  final hasUrl = photoUrl != null || frontUrl != null || backUrl != null;
  if (!hasText && !hasUrl) {
    throw DelegateProfileEditException(
      imageError ?? 'لم يتم تغيير أي بيان.',
    );
  }

  await edit(
    fullName: fullName,
    phoneNumber: phoneNumber,
    personalPhotoURL: photoUrl,
    nationalIdFrontUrl: frontUrl,
    nationalIdBackUrl: backUrl,
  );

  if (imageError != null) {
    return DelegateProfileSaveResult(
      saved: true,
      imagesFailed: true,
      message: hasText
          ? 'تم حفظ الاسم ورقم الموبايل، وتعذر رفع الصور. حاول رفع الصور مرة أخرى.'
          : imageError,
    );
  }
  return const DelegateProfileSaveResult(
    saved: true,
    message: 'تم حفظ تعديلات المندوب في كل السلاسل.',
  );
}

class DelegateProfileEditRepository {
  DelegateProfileEditRepository({
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  })  : _functionsOverride = functions,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage _storage;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<String> uploadImage({
    required String delegateUid,
    required String kind,
    required XFile file,
  }) async {
    final safeKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw DelegateProfileEditException('تعذر قراءة الصورة.');
    }
    final ref = _storage.ref(
      'delegate_documents/$delegateUid/${safeKind}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  Future<void> editProfile({
    required String companyUID,
    String? delegateUid,
    String? requestId,
    String? fullName,
    String? phoneNumber,
    String? personalPhotoURL,
    String? nationalIdFrontUrl,
    String? nationalIdBackUrl,
  }) async {
    await _call('editDelegateProfile', {
      'companyUID': companyUID,
      if (delegateUid != null && delegateUid.isNotEmpty) 'delegateUid': delegateUid,
      if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
      if (fullName != null && fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phoneNumber': phoneNumber.trim(),
      if (personalPhotoURL != null && personalPhotoURL.isNotEmpty)
        'personalPhotoURL': personalPhotoURL,
      if (nationalIdFrontUrl != null && nationalIdFrontUrl.isNotEmpty)
        'nationalIdFrontUrl': nationalIdFrontUrl,
      if (nationalIdBackUrl != null && nationalIdBackUrl.isNotEmpty)
        'nationalIdBackUrl': nationalIdBackUrl,
    });
  }

  Future<DelegateProfileSaveResult> saveProfile({
    required String companyUID,
    String? delegateUid,
    String? requestId,
    String? fullName,
    String? phoneNumber,
    XFile? personalPhoto,
    XFile? idFront,
    XFile? idBack,
  }) async {
    final id = (delegateUid != null && delegateUid.isNotEmpty)
        ? delegateUid
        : (requestId ?? 'unknown');
    final hasImages = personalPhoto != null || idFront != null || idBack != null;
    if (hasImages && id != 'unknown') {
      final intentError = await ensureStorageUploadIntent(
        firestore: FirebaseFirestore.instance,
        folderId: id,
        companyUID: companyUID,
        createdBy: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      if (intentError != null) {
        return DelegateProfileSaveResult(saved: false, message: intentError);
      }
    }
    return saveDelegateProfileEdit(
      upload: uploadImage,
      edit: ({
        String? fullName,
        String? phoneNumber,
        String? personalPhotoURL,
        String? nationalIdFrontUrl,
        String? nationalIdBackUrl,
      }) {
        return editProfile(
          companyUID: companyUID,
          delegateUid: delegateUid,
          requestId: requestId,
          fullName: fullName,
          phoneNumber: phoneNumber,
          personalPhotoURL: personalPhotoURL,
          nationalIdFrontUrl: nationalIdFrontUrl,
          nationalIdBackUrl: nationalIdBackUrl,
        );
      },
      delegateUid: id,
      fullName: fullName,
      phoneNumber: phoneNumber,
      personalPhoto: personalPhoto,
      idFront: idFront,
      idBack: idBack,
    );
  }

  Future<String> submitNationalIdUpdate({
    required String companyUID,
    required String newNationalId,
    String? delegateUid,
    String? requestId,
  }) async {
    final data = await _call('submitNationalIdUpdate', {
      'companyUID': companyUID,
      'newNationalId': newNationalId.trim(),
      if (delegateUid != null && delegateUid.isNotEmpty) 'delegateUid': delegateUid,
      if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
    });
    return (data['requestId'] ?? '').toString();
  }

  Future<void> reviewNationalIdUpdate({
    required String requestId,
    required bool approve,
    String? rejectionReason,
  }) async {
    await _call('reviewNationalIdUpdate', {
      'requestId': requestId,
      'approve': approve,
      if (rejectionReason != null && rejectionReason.trim().isNotEmpty)
        'rejectionReason': rejectionReason.trim(),
    });
  }

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> payload) async {
    try {
      final result = await _functions.httpsCallable(name).call(payload);
      final raw = result.data;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return {};
    } on FirebaseFunctionsException catch (e) {
      throw DelegateProfileEditException(callableErrorMessage(e));
    } catch (e) {
      throw DelegateProfileEditException('تعذر إتمام العملية. حاول مرة أخرى.');
    }
  }
}
