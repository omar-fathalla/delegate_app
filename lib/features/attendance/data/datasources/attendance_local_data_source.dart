import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_model.dart';

abstract class AttendanceLocalDataSource {
  Future<void> cacheAttendance(
    AttendanceModel attendanceToCache, [
    String? organizationId,
    String? userId,
  ]);
  Future<List<AttendanceModel>> getLastAttendanceHistory([
    String? organizationId,
    String? userId,
  ]);
  Future<void> updateAttendance(
    AttendanceModel attendanceToUpdate, [
    String? organizationId,
    String? userId,
  ]);
  Future<void> overwriteHistory(
    List<AttendanceModel> history, [
    String? organizationId,
    String? userId,
  ]);
  Future<void> clearAttendanceCache([String? userId]);
}

const cachedAttendance = 'cachedAttendance';

class AttendanceLocalDataSourceImpl implements AttendanceLocalDataSource {
  final SharedPreferences sharedPreferences;

  AttendanceLocalDataSourceImpl({required this.sharedPreferences});

  String _getKey(String? organizationId, [String? userId]) {
    final effectiveUser = (userId != null && userId.trim().isNotEmpty) ? userId.trim() : null;
    final effectiveOrg = (organizationId != null && organizationId.trim().isNotEmpty) ? organizationId.trim() : null;

    if (effectiveUser != null && effectiveOrg != null) {
      return 'cachedAttendance_${effectiveUser}_$effectiveOrg';
    } else if (effectiveUser != null) {
      return 'cachedAttendance_$effectiveUser';
    } else if (effectiveOrg != null) {
      return 'cachedAttendance_$effectiveOrg';
    }
    return cachedAttendance;
  }

  @override
  Future<void> cacheAttendance(
    AttendanceModel attendanceToCache, [
    String? organizationId,
    String? userId,
  ]) async {
    final history = await getLastAttendanceHistory(organizationId, userId);
    history.add(attendanceToCache);
    final jsonList = history.map((e) => json.encode(e.toJson())).toList();
    await sharedPreferences.setStringList(_getKey(organizationId, userId), jsonList);
  }

  @override
  Future<List<AttendanceModel>> getLastAttendanceHistory([
    String? organizationId,
    String? userId,
  ]) async {
    final jsonList = sharedPreferences.getStringList(_getKey(organizationId, userId));
    if (jsonList != null && jsonList.isNotEmpty) {
      final items = jsonList
          .map(
            (jsonStr) => AttendanceModel.fromJson(
              json.decode(jsonStr),
              json.decode(jsonStr)['id'] ?? '',
            ),
          )
          .toList();
      if (userId != null && userId.trim().isNotEmpty) {
        return items.where((e) => e.userId.isEmpty || e.userId == userId.trim()).toList();
      }
      return items;
    } else {
      return [];
    }
  }

  @override
  Future<void> updateAttendance(
    AttendanceModel attendanceToUpdate, [
    String? organizationId,
    String? userId,
  ]) async {
    final history = await getLastAttendanceHistory(organizationId, userId);
    final index = history.indexWhere((e) => e.id == attendanceToUpdate.id);
    if (index != -1) {
      history[index] = attendanceToUpdate;
      final jsonList = history.map((e) => json.encode(e.toJson())).toList();
      await sharedPreferences.setStringList(_getKey(organizationId, userId), jsonList);
    }
  }

  @override
  Future<void> overwriteHistory(
    List<AttendanceModel> history, [
    String? organizationId,
    String? userId,
  ]) async {
    final jsonList = history.map((e) => json.encode(e.toJson())).toList();
    await sharedPreferences.setStringList(_getKey(organizationId, userId), jsonList);
  }

  @override
  Future<void> clearAttendanceCache([String? userId]) async {
    final allKeys = sharedPreferences.getKeys();
    final prefix = (userId != null && userId.trim().isNotEmpty)
        ? 'cachedAttendance_${userId.trim()}'
        : 'cachedAttendance';
    for (final key in allKeys) {
      if (key == cachedAttendance || key.startsWith(prefix)) {
        await sharedPreferences.remove(key);
      }
    }
  }
}
