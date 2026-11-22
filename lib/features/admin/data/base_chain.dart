import 'package:cloud_firestore/cloud_firestore.dart';

/// TAS-254: the base chain («فتح الله ماركت», the free chain) that every new
/// delegate is registered under. Chains are added to the company and the
/// autoLink functions link each delegate to the rest of them, so the
/// add-delegate form no longer asks for chains.
///
/// Source: `config/subscriptions.freeChainOrgUids` (readable by any signed-in
/// user), the same list the autoLink and expiry functions use.
class BaseChain {
  const BaseChain({required this.uid, required this.name});

  final String uid;
  final String name;
}

/// First non-empty id in `freeChainOrgUids`, or null.
String? baseChainIdFromConfig(Map<String, dynamic>? config) {
  final raw = config?['freeChainOrgUids'];
  if (raw is! List) return null;
  for (final v in raw) {
    final id = v?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return null;
}

/// Reads the base chain id and its display name. Null when it is not set.
Future<BaseChain?> loadBaseChain(FirebaseFirestore firestore) async {
  final cfg = await firestore.doc('config/subscriptions').get();
  final id = baseChainIdFromConfig(cfg.data());
  if (id == null) return null;
  String name = id;
  try {
    final org = await firestore.collection('organizations').doc(id).get();
    final data = org.data();
    final n = (data?['name'] ?? data?['title'] ?? '').toString().trim();
    if (n.isNotEmpty) name = n;
  } catch (_) {
    // Name is display only; the id is what the request needs.
  }
  return BaseChain(uid: id, name: name);
}
