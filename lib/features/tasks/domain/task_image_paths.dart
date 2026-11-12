/// Maximum number of images a sender may attach to a task (Phase 3).
const int kMaxTaskImages = 3;

/// Resolve the attached image paths from either the Phase 3 list or the
/// legacy single [imagePath]. Empty entries are dropped; at most
/// [kMaxTaskImages] are kept. The list is the source of truth when present.
List<String> resolveTaskImagePaths({
  String? imagePath,
  List<String>? imagePaths,
}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String? raw) {
    final path = raw?.trim() ?? '';
    if (path.isEmpty || seen.contains(path)) return;
    seen.add(path);
    out.add(path);
  }

  if (imagePaths != null) {
    for (final path in imagePaths) {
      add(path);
    }
  }
  if (out.isEmpty) add(imagePath);
  if (out.length > kMaxTaskImages) {
    return List<String>.unmodifiable(out.take(kMaxTaskImages));
  }
  return List<String>.unmodifiable(out);
}
