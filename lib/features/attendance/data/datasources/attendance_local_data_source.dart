import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_model.dart';

abstract class AttendanceLocalDataSource {
  Future<void> cacheAttendance(AttendanceModel attendanceToCache, [String? organizationId]);
  Future<List<AttendanceModel>> getLastAttendanceHistory([String? organizationId]);
  Future<void> updateAttendance(AttendanceModel attendanceToUpdate, [String? organizationId]);
  Future<void> overwriteHistory(List<AttendanceModel> history, [String? organizationId]);
}

const cachedAttendance = 'cachedAttendance';

class AttendanceLocalDataSourceImpl implements AttendanceLocalDataSource {
  final SharedPreferences sharedPreferences;

  AttendanceLocalDataSourceImpl({required this.sharedPreferences});

  String _getKey(String? organizationId) {
    if (organizationId != null && organizationId.trim().isNotEmpty) {
      return 'cachedAttendance_${organizationId.trim()}';
    }
    return cachedAttendance;
  }

  @override
  Future<void> cacheAttendance(AttendanceModel attendanceToCache, [String? organizationId]) async {
    final history = await getLastAttendanceHistory(organizationId);
    history.add(attendanceToCache);
    final jsonList = history.map((e) => json.encode(e.toJson())).toList();
    await sharedPreferences.setStringList(_getKey(organizationId), jsonList);
  }

  @override
  Future<List<AttendanceModel>> getLastAttendanceHistory([String? organizationId]) async {
    final jsonList = sharedPreferences.getStringList(_getKey(organizationId));
    if (jsonList != null && jsonList.isNotEmpty) {
      return jsonList
          .map(
            (jsonStr) => AttendanceModel.fromJson(
              json.decode(jsonStr),
              json.decode(jsonStr)['id'] ?? '',
            ),
          )
          .toList();
    } else {
      return [];
    }
  }

  @override
  Future<void> updateAttendance(AttendanceModel attendanceToUpdate, [String? organizationId]) async {
    final history = await getLastAttendanceHistory(organizationId);
    final index = history.indexWhere((e) => e.id == attendanceToUpdate.id);
    if (index != -1) {
      history[index] = attendanceToUpdate;
      final jsonList = history.map((e) => json.encode(e.toJson())).toList();
      await sharedPreferences.setStringList(_getKey(organizationId), jsonList);
    }
  }

  @override
  Future<void> overwriteHistory(List<AttendanceModel> history, [String? organizationId]) async {
    final jsonList = history.map((e) => json.encode(e.toJson())).toList();
    await sharedPreferences.setStringList(_getKey(organizationId), jsonList);
  }
}
