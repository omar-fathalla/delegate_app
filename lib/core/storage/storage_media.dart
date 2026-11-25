import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// TAS-42: Firestore stores the Storage object path of an uploaded file,
/// not a `getDownloadURL()` link. A download URL carries a token that never
/// expires and is served without checking `storage.rules`; a path is turned
/// into a URL only at read time, through the rules, by a signed-in user who
/// may read it.
///
/// Old documents still hold URLs, so every reader accepts either form
/// ("path or URL") and [StorageMediaResolver] makes it displayable.
abstract final class StorageMediaRef {
  static bool isRemoteUrl(String value) {
    final v = value.trim();
    return v.startsWith('https://') || v.startsWith('http://');
  }

  /// True for a Storage object path such as `feedback_screenshots/a.jpg`
  /// or `gs://bucket/a.jpg`. Local files (`/data/...`, `file:`, `content:`),
  /// bundled assets, URLs and empty values are not Storage paths.
  static bool isStoragePath(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty || isRemoteUrl(v)) return false;
    if (v.startsWith('gs://')) return true;
    if (v.startsWith('/') ||
        v.startsWith('file:') ||
        v.startsWith('content:') ||
        v.startsWith('assets/') ||
        v.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(v)) {
      return false;
    }
    return v.contains('/');
  }

  /// The value to keep in an entity for display: the path when the doc has
  /// one, otherwise the legacy URL. Empty when neither is set.
  ///
  /// When a doc has both, the URL is remembered as the fallback for that
  /// path: a reader the Storage rules do not (yet) allow still sees the
  /// file while new uploads keep writing the legacy URL
  /// ([LegacyStorageUrls]), exactly as before this change.
  static String pick({Object? path, Object? url}) {
    final p = path is String ? path.trim() : '';
    final u = url is String ? url.trim() : '';
    if (p.isNotEmpty) {
      if (u.isNotEmpty && isRemoteUrl(u)) rememberLegacyUrl(p, u);
      return p;
    }
    return u;
  }

  /// TAS-331: like [pick], for fields an older writer may still overwrite
  /// by URL only (delegate documents: old store builds, the HR web and
  /// callables replace `documentURL` and leave the entry's previous
  /// `documentPath` in place). The path wins unless the URL is a Firebase
  /// download URL of a different object: then the URL is newer.
  static String pickFresh({Object? path, Object? url}) {
    final p = path is String ? path.trim() : '';
    final u = url is String ? url.trim() : '';
    if (p.isEmpty) return u;
    if (u.isEmpty) return p;
    final urlObject = pathFromDownloadUrl(u);
    if (urlObject != null && urlObject != objectPath(p)) return u;
    return pick(path: p, url: u);
  }

  /// [value] without a `gs://bucket/` prefix.
  static String objectPath(String value) {
    final v = value.trim();
    if (!v.startsWith('gs://')) return v;
    final rest = v.substring(5);
    final slash = rest.indexOf('/');
    return slash < 0 ? '' : rest.substring(slash + 1);
  }

  static final Map<String, String> _legacyUrls = <String, String>{};
  static const int _maxLegacyUrls = 3000;

  /// Records [url] as the fallback for [path] (see [pick]).
  static void rememberLegacyUrl(String path, String url) {
    final key = path.trim();
    if (key.isEmpty || url.trim().isEmpty) return;
    _legacyUrls.remove(key);
    _legacyUrls[key] = url.trim();
    while (_legacyUrls.length > _maxLegacyUrls) {
      _legacyUrls.remove(_legacyUrls.keys.first);
    }
  }

  /// The legacy URL stored next to [path], if a doc carried both.
  static String? legacyUrlFor(String path) => _legacyUrls[path.trim()];

  @visibleForTesting
  static void clearLegacyUrls() => _legacyUrls.clear();

  /// Object path inside a Firebase Storage download URL
  /// (`https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?...`),
  /// or null for any other value.
  static String? pathFromDownloadUrl(String? url) {
    final v = (url ?? '').trim();
    if (!isRemoteUrl(v)) return null;
    final uri = Uri.tryParse(v);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final o = segments.indexOf('o');
    if (o < 0 || o + 1 >= segments.length) return null;
    if (o < 3 || segments[0] != 'v0' || segments[1] != 'b') return null;
    final path = segments.sublist(o + 1).join('/');
    return path.isEmpty ? null : path;
  }

  /// A [Reference] for a stored value: a Storage path, `gs://` or a
  /// Firebase download URL. Null for local files, assets and empty values.
  static Reference? refFor(FirebaseStorage storage, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (isRemoteUrl(v) || v.startsWith('gs://')) {
      try {
        return storage.refFromURL(v);
      } catch (_) {
        return null;
      }
    }
    if (!isStoragePath(v)) return null;
    return storage.ref(v);
  }
}

/// Resolves a stored "path or URL" to something an image widget or a
/// browser can open. Paths go through `getDownloadURL()` (checked by the
/// Storage rules); URLs, local files and assets are returned unchanged.
///
/// Results are cached per path for [ttl] and concurrent calls share one
/// request. Failures are not cached, so a later call retries.
class StorageMediaResolver {
  StorageMediaResolver({
    Future<String> Function(String path)? downloadUrlFor,
    this.ttl = const Duration(minutes: 50),
    this.maxEntries = 400,
    DateTime Function()? now,
  }) : _downloadUrlFor = downloadUrlFor ?? _firebaseDownloadUrl,
       _now = now ?? DateTime.now;

  static StorageMediaResolver? _instance;

  /// Tests set this to avoid Firebase.
  @visibleForTesting
  static StorageMediaResolver? debugOverride;

  static StorageMediaResolver get instance =>
      debugOverride ?? (_instance ??= StorageMediaResolver());

  final Future<String> Function(String path) _downloadUrlFor;
  final DateTime Function() _now;
  final Duration ttl;
  final int maxEntries;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static Future<String> _firebaseDownloadUrl(String path) {
    final storage = FirebaseStorage.instance;
    final ref = path.startsWith('gs://')
        ? storage.refFromURL(path)
        : storage.ref(path);
    return ref.getDownloadURL();
  }

  /// The URL cached for [path], if still fresh (no network).
  String? cachedUrl(String path) {
    final e = _cache[path.trim()];
    if (e == null || e.url == null || e.expiresAt.isBefore(_now())) return null;
    return e.url;
  }

  /// Null for null / empty input. Throws when a path cannot be resolved
  /// (for example the rules deny the read).
  Future<String?> resolve(String? pathOrUrl) async {
    final v = (pathOrUrl ?? '').trim();
    if (v.isEmpty) return null;
    if (!StorageMediaRef.isStoragePath(v)) return v;

    final hit = _cache[v];
    if (hit != null && hit.expiresAt.isAfter(_now())) {
      if (hit.url != null) return hit.url;
      if (hit.pending != null) return hit.pending;
    }

    final future = _load(v);
    _cache[v] = _CacheEntry.pending(future, _now().add(ttl));
    try {
      final url = await future;
      _cache[v] = _CacheEntry.done(url, _now().add(ttl));
      _trim();
      return url;
    } catch (_) {
      _cache.remove(v);
      rethrow;
    }
  }

  /// The rules decide first; a denied or failed lookup falls back to the
  /// legacy URL the same doc carried, if any.
  Future<String> _load(String path) async {
    try {
      return await _downloadUrlFor(path);
    } catch (e) {
      final legacy = StorageMediaRef.legacyUrlFor(path);
      if (legacy != null) {
        debugPrint('storage_media: path not readable, using legacy URL ($e)');
        return legacy;
      }
      rethrow;
    }
  }

  /// Like [resolve] but returns null instead of throwing.
  Future<String?> tryResolve(String? pathOrUrl) async {
    try {
      return await resolve(pathOrUrl);
    } catch (e) {
      debugPrint('storage_media resolve failed: $e');
      return null;
    }
  }

  void evict(String path) => _cache.remove(path.trim());

  @visibleForTesting
  void clear() => _cache.clear();

  @visibleForTesting
  int get cacheSize => _cache.length;

  void _trim() {
    if (_cache.length <= maxEntries) return;
    final now = _now();
    _cache.removeWhere((_, e) => e.expiresAt.isBefore(now));
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

class _CacheEntry {
  _CacheEntry.pending(this.pending, this.expiresAt) : url = null;
  _CacheEntry.done(this.url, this.expiresAt) : pending = null;

  final Future<String>? pending;
  final String? url;
  final DateTime expiresAt;
}

/// Whether new uploads also write the old download-URL field next to the
/// new path field, for app versions older than this change (they only read
/// the URL field). Remote Config `write_legacy_storage_urls`; missing,
/// unreadable or anything but `false` / `0` means on.
///
/// Turn it off only after the forced-update minimum (`min_app_version_*`)
/// is at or above the first release that reads paths.
abstract final class LegacyStorageUrls {
  static const String remoteConfigKey = 'write_legacy_storage_urls';

  @visibleForTesting
  static bool? debugOverride;

  static bool get enabled {
    final forced = debugOverride;
    if (forced != null) return forced;
    try {
      final value = FirebaseRemoteConfig.instance.getValue(remoteConfigKey);
      if (value.source == ValueSource.valueStatic) return true;
      final s = value.asString().trim().toLowerCase();
      return !(s == 'false' || s == '0');
    } catch (_) {
      return true;
    }
  }

  /// The legacy URL for a just-uploaded [ref], or null when the flag is off
  /// or the URL cannot be read (the path is the source of truth).
  static Future<String?> urlFor(Reference ref) async {
    if (!enabled) return null;
    try {
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('legacy download URL skipped: $e');
      return null;
    }
  }
}
