import 'package:cloud_functions/cloud_functions.dart';

class SupervisorDocReuploadException implements Exception {
  SupervisorDocReuploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Server-side supervisor active→pending document replace (Mohamed 2026-11-15).
class SupervisorDelegateDocReuploadRemote {
  SupervisorDelegateDocReuploadRemote({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

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
            : 'تعذر تحديث المستند. حاول مرة أخرى.',
      );
    } catch (_) {
      throw SupervisorDocReuploadException('تعذر تحديث المستند. حاول مرة أخرى.');
    }
  }
}