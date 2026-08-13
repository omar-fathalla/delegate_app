import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// A wrapper around [SharedPreferences] that provides a consistent API
/// for storing sensitive data.
///
/// **Migration note:** When `flutter_secure_storage` is added to the project,
/// replace the internal implementation with [FlutterSecureStorage] while
/// keeping the same public interface — no call-site changes required.
///
/// ```yaml
/// # pubspec.yaml – add when ready:
/// # flutter_secure_storage: ^9.2.4
/// ```
class SecureStorageService {
  final SharedPreferences _prefs;

  // Key prefix to namespace secure entries.
  static const _prefix = 'secure_';

  SecureStorageService({required SharedPreferences prefs}) : _prefs = prefs;

  /// Writes a [value] for the given [key].
  Future<void> write({required String key, required String value}) async {
    // In a production app with flutter_secure_storage, this would be:
    // await _secureStorage.write(key: key, value: value);
    await _prefs.setString('$_prefix$key', value);
  }

  /// Reads the value for the given [key]. Returns `null` if not found.
  Future<String?> read({required String key}) async {
    return _prefs.getString('$_prefix$key');
  }

  /// Deletes the value for the given [key].
  Future<void> delete({required String key}) async {
    await _prefs.remove('$_prefix$key');
  }

  /// Writes a JSON-serializable [Map] for the given [key].
  Future<void> writeJson({
    required String key,
    required Map<String, dynamic> value,
  }) async {
    try {
      await write(key: key, value: jsonEncode(value));
    } catch (e, st) {
      developer.log(
        'Failed to write secure JSON',
        name: 'SecureStorageService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Reads a JSON-serializable [Map] for the given [key].
  Future<Map<String, dynamic>?> readJson({required String key}) async {
    try {
      final raw = await read(key: key);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      developer.log(
        'Failed to read secure JSON',
        name: 'SecureStorageService',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Clears all secure entries.
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
