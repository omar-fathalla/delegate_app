import 'package:cloud_firestore/cloud_firestore.dart';

/// Writes [storage_upload_intents/{folderId}] before a staff upload to
/// `delegate_documents/{folderId}`. Storage rules use this doc as the
/// company tenant check. The doc is immutable to clients; a mismatch
/// with an existing intent is fail-closed.
Future<String?> ensureStorageUploadIntent({
  required FirebaseFirestore firestore,
  required String folderId,
  required String companyUID,
  required String createdBy,
}) async {
  final id = folderId.trim();
  final company = companyUID.trim();
  final uid = createdBy.trim();
  if (id.isEmpty) return 'تعذر تحديد مجلد المستندات.';
  if (company.isEmpty) return 'اختر الشركة أولاً ثم أعد المحاولة.';
  if (uid.isEmpty) return 'تعذر تحديد المستخدم.';
  final ref = firestore.collection('storage_upload_intents').doc(id);
  final existing = await ref.get();
  if (existing.exists) {
    final existingCompany =
        (existing.data()?['companyUID'] ?? '').toString().trim();
    if (existingCompany != company) {
      return 'لا يمكن رفع المستندات لمجلد يخص شركة أخرى.';
    }
    return null;
  }
  await ref.set({
    'companyUID': company,
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return null;
}
