/// Multi-chain selection for the supervisor add-delegate flow.
/// Company is the tenant: one request, one approval, one subscription.
library;

const int kMaxOrganizationsPerRequest = 10;

class ChainOption {
  const ChainOption({required this.uid, required this.name});
  final String uid;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ChainOption && other.uid == uid && other.name == name;

  @override
  int get hashCode => Object.hash(uid, name);
}

class ChainSelectionResult {
  const ChainSelectionResult({
    required this.kept,
    required this.skipped,
    this.droppedOverMax = const [],
  });

  /// Chains that will be written on the request (duplicates removed, cap applied).
  final List<ChainOption> kept;

  /// Selected chains the person is already on (or has a pending request for).
  final List<ChainOption> skipped;

  /// Selected chains dropped because of [kMaxOrganizationsPerRequest].
  final List<ChainOption> droppedOverMax;

  bool get canSubmit => kept.isNotEmpty;

  String? get primaryUid => kept.isEmpty ? null : kept.first.uid;
  String? get primaryName => kept.isEmpty ? null : kept.first.name;
  List<String> get keptUids => kept.map((c) => c.uid).toList();
  List<String> get keptNames => kept.map((c) => c.name).toList();
  List<String> get skippedUids => skipped.map((c) => c.uid).toList();

  /// Arabic warning. Null when there is nothing to warn about.
  String? get warningAr {
    if (skipped.isEmpty && droppedOverMax.isEmpty) return null;
    final parts = <String>[];
    if (skipped.isNotEmpty) {
      final skippedNames = skipped.map((c) => c.name).join('، ');
      if (kept.isEmpty) {
        parts.add('المندوب مسجل بالفعل في كل السلاسل المختارة: $skippedNames. لن يتم إرسال الطلب.');
      } else {
        final keptNames = kept.map((c) => c.name).join('، ');
        parts.add('المندوب مسجل بالفعل في: $skippedNames. سيتم تسجيله في: $keptNames.');
      }
    }
    if (droppedOverMax.isNotEmpty) {
      parts.add('الحد الأقصى $kMaxOrganizationsPerRequest سلاسل في الطلب الواحد. لم تُضف: ${droppedOverMax.map((c) => c.name).join('، ')}.');
    }
    return parts.join(' ');
  }
}

/// Keeps selection order, skips [duplicateUids], and caps at [max].
ChainSelectionResult partitionSelectedChains({
  required List<ChainOption> all,
  required Set<String> selectedUids,
  Set<String> duplicateUids = const {},
  int max = kMaxOrganizationsPerRequest,
}) {
  final byUid = {for (final c in all) c.uid: c};
  final skipped = <ChainOption>[];
  final kept = <ChainOption>[];
  final dropped = <ChainOption>[];
  final seen = <String>{};
  for (final uid in selectedUids) {
    final chain = byUid[uid];
    if (chain == null || !seen.add(uid)) continue;
    if (duplicateUids.contains(uid)) {
      skipped.add(chain);
      continue;
    }
    if (kept.length >= max) {
      dropped.add(chain);
      continue;
    }
    kept.add(chain);
  }
  return ChainSelectionResult(kept: kept, skipped: skipped, droppedOverMax: dropped);
}

/// Toggle "select all": if every available chain is already selected, clear;
/// otherwise select all (the cap is applied later at partition/submit).
Set<String> toggleSelectAll({
  required List<ChainOption> all,
  required Set<String> selectedUids,
}) {
  final ids = all.map((c) => c.uid).toSet();
  if (ids.isEmpty) return {};
  if (ids.difference(selectedUids).isEmpty) return {};
  return {...selectedUids, ...ids};
}

/// Resolve organizationUIDs from a request, including the legacy single field.
List<String> resolveOrganizationUIDs({
  required String organizationUID,
  List<String> organizationUIDs = const [],
  int max = kMaxOrganizationsPerRequest,
}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) return;
    if (out.length < max) out.add(id);
  }

  for (final id in organizationUIDs) {
    add(id);
  }
  final primary = organizationUID.trim();
  if (primary.isNotEmpty && !seen.contains(primary)) {
    out.insert(0, primary);
    if (out.length > max) {
      out.removeLast();
    }
  }
  if (out.isEmpty && primary.isNotEmpty) return [primary];
  return out;
}
