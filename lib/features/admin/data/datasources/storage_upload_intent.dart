import 'package:cloud_functions/cloud_functions.dart';

/// Asks the [ensureStorageUploadIntent] callable to bind
/// `storage_upload_intents/{folderId}` to the folder's owning company
/// before a staff upload to `delegate_documents/{folderId}`.
///
/// The callable verifies an existing request or delegate, or reserves a
/// new folder for the caller's company. Clients no longer read-or-create
/// the intent (a get of a missing doc was permission-denied, and a client
/// create could claim another company's folder).
Future<String?> ensureStorageUploadIntent({
  required String folderId,
  required String companyUID,
  FirebaseFunctions? functions,
}) async {
  final id = folderId.trim();
  final company = companyUID.trim();
  if (id.isEmpty) return 'تعذر تحديد مجلد المستندات.';
  if (company.isEmpty) return 'اختر الشركة أولاً ثم أعد المحاولة.';
  try {
    final callable =
        (functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'))
            .httpsCallable('ensureStorageUploadIntent');
    await callable.call({'folderId': id, 'companyUID': company});
    return null;
  } on FirebaseFunctionsException catch (e) {
    return _intentErrorMessage(e);
  } catch (_) {
    return 'تعذر تجهيز مجلد المستندات. أعد المحاولة.';
  }
}

String _intentErrorMessage(FirebaseFunctionsException e) {
  final reason =
      (e.details is Map ? (e.details as Map)['reason'] : null)?.toString() ??
      e.message ??
      e.code;
  switch (reason) {
    case 'folder_other_company':
    case 'company_mismatch':
      return 'لا يمكن رفع المستندات لمجلد يخص شركة أخرى.';
    case 'sign_in_required':
    case 'unauthenticated':
      return 'يجب تسجيل الدخول أولاً.';
    case 'caller_not_staff':
    case 'caller_no_company':
      return 'ليس لديك صلاحية رفع مستندات لهذا المجلد.';
    case 'company_required':
      return 'اختر الشركة أولاً ثم أعد المحاولة.';
    case 'folder_id_required':
      return 'تعذر تحديد مجلد المستندات.';
    default:
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        return 'ليس لديك صلاحية رفع مستندات لهذا المجلد.';
      }
      return 'تعذر تجهيز مجلد المستندات. أعد المحاولة.';
  }
}
