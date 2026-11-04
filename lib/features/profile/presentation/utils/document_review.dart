/// Docs-pending helpers (Mohamed 2026-11-04).
///
/// A delegate's own re-upload is written as `pending`; only an approver
/// (super-admin, or company admin/supervisor of the same company) may write
/// `approved`. Every other entry is copied exactly as stored so the
/// Firestore rule "an approved entry must be carried over unchanged" passes
/// and no fields (receiptCode, reviewedBy, rejectionReason...) are lost.
library;

/// Maps the screen's docType to the stored documentKey.
String documentKeyForDocType(String docType) {
  switch (docType) {
    case 'nationalIdFront':
    case 'nationalIdBack':
      return 'nationalityId';
    default:
      return docType;
  }
}

List<Map<String, dynamic>> _copyEntries(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return [
    for (final e in raw)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// Returns the new `documents` list after re-uploading [docType] with [newUrl].
/// [approverUid] null means the caller is the delegate (or a non-approver):
/// the entry is written as `pending`.
List<Map<String, dynamic>> mergeReuploadedDocument(
  dynamic raw, {
  required String docType,
  required String newUrl,
  String? approverUid,
  DateTime? now,
}) {
  final ts = (now ?? DateTime.now()).toIso8601String();
  final key = documentKeyForDocType(docType);
  final docs = _copyEntries(raw);
  final idx = docs.indexWhere((d) => d['documentKey'] == key);
  final Map<String, dynamic> base = idx >= 0
      ? Map<String, dynamic>.from(docs[idx])
      : {'documentKey': key};

  if (docType == 'nationalIdFront') {
    base['documentURL'] = newUrl;
    base.putIfAbsent('secondaryURL', () => '');
  } else if (docType == 'nationalIdBack') {
    base['secondaryURL'] = newUrl;
    base.putIfAbsent('documentURL', () => '');
  } else {
    base['documentURL'] = newUrl;
  }
  base['uploadedAt'] = ts;
  base.remove('rejectionReason');
  if (approverUid != null) {
    base['documentStatus'] = 'approved';
    base['reviewedBy'] = approverUid;
    base['reviewedAt'] = ts;
  } else {
    base['documentStatus'] = 'pending';
    base.remove('reviewedBy');
    base.remove('reviewedAt');
  }

  if (idx >= 0) {
    docs[idx] = base;
  } else {
    docs.add(base);
  }
  return docs;
}

/// Staff approve / reject of the entry for [docType]. Returns null when the
/// list has no such entry.
List<Map<String, dynamic>>? reviewDocumentEntry(
  dynamic raw, {
  required String docType,
  required bool approve,
  required String reviewerUid,
  String? rejectionReason,
  DateTime? now,
}) {
  final key = documentKeyForDocType(docType);
  final docs = _copyEntries(raw);
  final idx = docs.indexWhere((d) => d['documentKey'] == key);
  if (idx < 0) return null;
  final e = Map<String, dynamic>.from(docs[idx]);
  e['documentStatus'] = approve ? 'approved' : 'rejected';
  e['reviewedBy'] = reviewerUid;
  e['reviewedAt'] = (now ?? DateTime.now()).toIso8601String();
  if (approve) {
    e.remove('rejectionReason');
  } else {
    e['rejectionReason'] = rejectionReason ?? '';
  }
  docs[idx] = e;
  return docs;
}
