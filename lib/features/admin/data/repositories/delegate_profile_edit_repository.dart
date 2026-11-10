import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DelegateProfileEditException implements Exception {
  DelegateProfileEditException(this.message);
  final String message;

  @override
  String toString() => message;
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
    required File file,
  }) async {
    final safeKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final ref = _storage.ref(
      'delegate_documents/$delegateUid/${safeKind}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putFile(file);
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
      final message = (e.message ?? '').trim();
      throw DelegateProfileEditException(
        message.isNotEmpty ? message : 'تعذر إتمام العملية. حاول مرة أخرى.',
      );
    } catch (e) {
      throw DelegateProfileEditException('تعذر إتمام العملية. حاول مرة أخرى.');
    }
  }
}
