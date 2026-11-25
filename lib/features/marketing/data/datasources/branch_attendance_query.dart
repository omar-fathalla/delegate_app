import 'package:cloud_firestore/cloud_firestore.dart';

/// TAS-335: the branches screen finds today's attendance by `branchId` and by
/// `branchName`, so a log whose name is spelled differently from the favorite
/// (for example «الإبراهيميه» vs «الابراهيمية») is still found through its
/// `branchId`. The name terms stay for legacy logs written without a
/// `branchId`.
///
/// Both lists go into one `Filter.or` per chunk, so Firestore returns (and
/// bills) each matching log once even when it matches by id and by name.

/// Firestore allows at most 30 disjunctions per query. Every `whereIn` value
/// is one disjunction, so the ids plus the name terms of a chunk stay <= 30.
const int kMaxAttendanceDisjunctions = 30;

/// Same normalization as `MarketingRemoteDataSourceImpl.normalizeBranchName`.
String normalizeAttendanceBranchName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Maps each favorite branch name to the ids of the catalog branches whose
/// normalized name matches it. [catalog] holds `(id, name)` pairs from the
/// `branches` collection. Favorites with no match get an empty set and are
/// found by name only.
Map<String, Set<String>> resolveFavoriteBranchIds(
  List<String> favorites,
  Iterable<({String id, String name})> catalog,
) {
  final byNormalized = <String, Set<String>>{};
  for (final b in catalog) {
    final id = b.id.trim();
    final key = normalizeAttendanceBranchName(b.name);
    if (id.isEmpty || key.isEmpty) continue;
    byNormalized.putIfAbsent(key, () => <String>{}).add(id);
  }
  return {
    for (final f in favorites)
      if (f.trim().isNotEmpty)
        f: {...?byNormalized[normalizeAttendanceBranchName(f)]},
  };
}

/// One attendance query: the branch ids and name terms it matches.
class BranchAttendanceChunk {
  final List<String> branchIds;
  final List<String> branchNames;

  const BranchAttendanceChunk({
    required this.branchIds,
    required this.branchNames,
  });

  int get disjunctions => branchIds.length + branchNames.length;

  /// `branchId in ids OR branchName in names` (only the non-empty parts).
  Filter get filter {
    final byId = branchIds.isEmpty
        ? null
        : Filter('branchId', whereIn: branchIds);
    final byName = branchNames.isEmpty
        ? null
        : Filter('branchName', whereIn: branchNames);
    if (byId != null && byName != null) return Filter.or(byId, byName);
    return byId ?? byName!;
  }
}

/// Groups the favorites into chunks of at most [maxDisjunctions] values.
/// A favorite's ids and name terms stay in the same chunk.
List<BranchAttendanceChunk> buildBranchAttendanceChunks({
  required List<String> favorites,
  required Map<String, Set<String>> idsByFavorite,
  required Set<String> Function(String favorite) nameTerms,
  int maxDisjunctions = kMaxAttendanceDisjunctions,
}) {
  final chunks = <BranchAttendanceChunk>[];
  var ids = <String>{};
  var names = <String>{};

  void flush() {
    if (ids.isEmpty && names.isEmpty) return;
    chunks.add(
      BranchAttendanceChunk(
        branchIds: ids.toList(),
        branchNames: names.toList(),
      ),
    );
    ids = <String>{};
    names = <String>{};
  }

  for (final f in favorites) {
    if (f.trim().isEmpty) continue;
    final fIds = (idsByFavorite[f] ?? const <String>{}).difference(ids);
    final fNames = nameTerms(f).difference(names);
    if (ids.length + names.length + fIds.length + fNames.length >
        maxDisjunctions) {
      flush();
    }
    // A single favorite never has close to 30 values (<= 6 name terms), but
    // split defensively so no query goes over the limit.
    for (final id in fIds) {
      if (ids.length + names.length >= maxDisjunctions) flush();
      ids.add(id);
    }
    for (final n in fNames) {
      if (ids.length + names.length >= maxDisjunctions) flush();
      names.add(n);
    }
  }
  flush();
  return chunks;
}

/// The favorite a log belongs to: by `branchId` first (spelling-proof), then
/// by normalized `branchName` (legacy logs without an id). Null when neither
/// matches a favorite.
String? favoriteForAttendanceLog(
  Map<String, dynamic> data, {
  required Map<String, String> favoriteById,
  required Map<String, String> favoriteByNormalizedName,
}) {
  final id = (data['branchId'] as String?)?.trim() ?? '';
  if (id.isNotEmpty) {
    final byId = favoriteById[id];
    if (byId != null) return byId;
  }
  final raw = data['branchName'] as String? ?? '';
  return favoriteByNormalizedName[normalizeAttendanceBranchName(raw)];
}

/// Inverts [idsByFavorite] (an id shared by two favorites keeps the first).
Map<String, String> favoriteByBranchId(Map<String, Set<String>> idsByFavorite) {
  final out = <String, String>{};
  idsByFavorite.forEach((favorite, ids) {
    for (final id in ids) {
      out.putIfAbsent(id, () => favorite);
    }
  });
  return out;
}

/// Concatenates query results, keeping the first copy of each document id.
List<QueryDocumentSnapshot<Map<String, dynamic>>> dedupeAttendanceDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final seen = <String>{};
  return [
    for (final d in docs)
      if (seen.add(d.reference.path)) d,
  ];
}

/// Everything the branches screen needs to query and attribute today's logs.
class BranchAttendancePlan {
  final List<BranchAttendanceChunk> chunks;
  final Map<String, String> favoriteById;
  final Map<String, String> favoriteByNormalizedName;

  const BranchAttendancePlan({
    required this.chunks,
    required this.favoriteById,
    required this.favoriteByNormalizedName,
  });

  /// [nameTerms] defaults to the Arabic spelling variants of each favorite.
  factory BranchAttendancePlan.build(
    List<String> favorites,
    Iterable<({String id, String name})> catalog, {
    Set<String> Function(String favorite)? nameTerms,
  }) {
    final ids = resolveFavoriteBranchIds(favorites, catalog);
    return BranchAttendancePlan(
      chunks: buildBranchAttendanceChunks(
        favorites: favorites,
        idsByFavorite: ids,
        nameTerms: nameTerms ?? branchNameSpellings,
      ),
      favoriteById: favoriteByBranchId(ids),
      favoriteByNormalizedName: {
        for (final f in favorites)
          if (f.trim().isNotEmpty) normalizeAttendanceBranchName(f): f,
      },
    );
  }

  String? favoriteFor(Map<String, dynamic> data) => favoriteForAttendanceLog(
    data,
    favoriteById: favoriteById,
    favoriteByNormalizedName: favoriteByNormalizedName,
  );
}

/// Spellings of one branch name sent to `branchName whereIn` (same variants
/// as `branchQueryTerms`).
Set<String> branchNameSpellings(String branch) {
  final trimmed = branch.trim();
  if (trimmed.isEmpty) return {};
  return {
    trimmed,
    trimmed.replaceAll(RegExp(r'[أإآ]'), 'ا'),
    trimmed.replaceAll('ا', 'أ'),
    trimmed.replaceAll('ه', 'ة'),
    trimmed.replaceAll('ة', 'ه'),
    trimmed.replaceAll('ى', 'ي'),
  };
}
