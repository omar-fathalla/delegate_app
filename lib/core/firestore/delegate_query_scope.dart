import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Adds the caller's organization/company filter to collection-group
/// `delegates` queries (Phase 1b).
///
/// The Phase 1b Firestore rules only allow a delegates list query when the
/// rules can prove every result is in the caller's scope:
///   * global staff (super-admin / technical support): no filter needed
///   * org-bound staff: `organizationUID == <own org>`
///   * company staff without an org: `companyUID == <own company>`
///   * delegates (delegateLoginV2 claims): `companyUID == <claim company>`
///
/// The scope is read once per signed-in uid from the ID token claims
/// (delegates) or `users/{uid}` (staff) and cached.
class DelegateQueryScope {
  DelegateQueryScope._();

  static const _globalRoles = {
    'super-admin', 'super_admin', 'superadmin', 'superAdmin',
    'technical_support', 'technical-support', 'technicalSupport', 'tech_support',
  };

  static String? _uid;
  static bool _global = false;
  static String _org = '';
  static String _company = '';
  static List<String> _companies = const [];
  static Future<void>? _loading;

  static void reset() {
    _uid = null;
    _global = false;
    _org = '';
    _company = '';
    _companies = const [];
    _loading = null;
  }

  static Future<void> ensureLoaded({FirebaseAuth? auth, FirebaseFirestore? firestore}) {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      reset();
      return Future.value();
    }
    if (_uid == user.uid && _loading != null) return _loading!;
    _uid = user.uid;
    _loading = _load(user, firestore ?? FirebaseFirestore.instance);
    return _loading!;
  }

  static Future<void> _load(User user, FirebaseFirestore firestore) async {
    _global = false;
    _org = '';
    _company = '';
    _companies = const [];
    try {
      final claims = (await user.getIdTokenResult()).claims ?? const {};
      if (claims['role'] == 'delegate') {
        _org = (claims['orgId'] ?? '').toString();
        _company = (claims['companyId'] ?? '').toString();
        final many = claims['companyIds'];
        if (many is List) _companies = many.map((e) => e.toString()).toList();
        _org = ''; // delegates are scoped by company, not org
        return;
      }
      final snap = await firestore.collection('users').doc(user.uid).get();
      final d = snap.data() ?? const <String, dynamic>{};
      final role = (d['role'] ?? '').toString();
      _global = _globalRoles.contains(role);
      _org = (d['organizationUID'] ?? d['organizationId'] ?? '').toString();
      _company = (d['companyUID'] ?? d['companyId'] ?? '').toString();
    } catch (e) {
      debugPrint('DelegateQueryScope load failed: $e');
      _loading = null; // retry next time
    }
  }

  /// Applies the scope filter to [query] (a `delegates` collection-group or
  /// root query). Global staff get the query unchanged.
  static Query<Map<String, dynamic>> apply(Query<Map<String, dynamic>> query) {
    if (_global) return query;
    if (_org.isNotEmpty) return query.where('organizationUID', isEqualTo: _org);
    if (_companies.length > 1) return query.where('companyUID', whereIn: _companies.take(30).toList());
    if (_company.isNotEmpty) return query.where('companyUID', isEqualTo: _company);
    return query;
  }

  /// `collectionGroup('delegates')` with the caller's scope filter.
  static Future<Query<Map<String, dynamic>>> collectionGroup(FirebaseFirestore firestore) async {
    await ensureLoaded(firestore: firestore);
    return apply(firestore.collectionGroup('delegates'));
  }

  @visibleForTesting
  static void debugSet({bool global = false, String org = '', String company = '', List<String> companies = const []}) {
    _uid = 'debug';
    _loading = Future.value();
    _global = global;
    _org = org;
    _company = company;
    _companies = companies;
  }
}

/// Sync shortcut for call sites that build queries inline. Uses the cached
/// scope (loaded on every auth/token change from `main.dart`). If the scope is
/// not loaded yet the query is unfiltered, which Phase 1b rules deny (fail closed).
extension ScopedDelegatesGroup on FirebaseFirestore {
  Query<Map<String, dynamic>> scopedDelegatesGroup() =>
      DelegateQueryScope.apply(collectionGroup('delegates'));
}
