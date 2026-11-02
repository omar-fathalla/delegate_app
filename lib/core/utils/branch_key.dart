/// Normalized branch key stored on every `attendance_logs` write as
/// `branchKey`, so readers can query one value per branch instead of
/// several Arabic spelling variants of `branchName`.
///
/// Rules (single source of truth, also used by
/// `MarketingRemoteDataSourceImpl.normalizeBranchName`):
/// trim → lowercase → `[أإآ]→ا`, `ة→ه`, `ى→ي` → collapse whitespace.
String branchKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Returns `{'branchKey': key}` for a non-empty branch name, otherwise `{}`.
/// Spread into attendance payloads: `...branchKeyField(branchName)`.
Map<String, String> branchKeyField(Object? branchName) {
  if (branchName is! String) return const {};
  final key = branchKey(branchName);
  return key.isEmpty ? const {} : {'branchKey': key};
}
