import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_model.dart';

abstract class AttendanceLocalDataSource {
  Future<void> cacheAttendance(AttendanceModel attendanceToCache);
  Future<List<AttendanceModel>> getLastAttendanceHistory();
  Future<void> updateAttendance(AttendanceModel attendanceToUpdate);
}

const cachedAttendance = 'cachedAttendance';

class AttendanceLocalDataSourceImpl implements AttendanceLocalDataSource {
  final SharedPreferences sharedPreferences;

  AttendanceLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheAttendance(AttendanceModel attendanceToCache) async {
    final history = await getLastAttendanceHistory();
    history.add(attendanceToCache);
    final jsonList = history.map((e) => json.encode(e.toJson())).toList();
    await sharedPreferences.setStringList(cachedAttendance, jsonList);
  }

  @override
  Future<List<AttendanceModel>> getLastAttendanceHistory() async {
    final jsonList = sharedPreferences.getStringList(cachedAttendance);
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
  Future<void> updateAttendance(AttendanceModel attendanceToUpdate) async {
    final history = await getLastAttendanceHistory();
    final index = history.indexWhere((e) => e.id == attendanceToUpdate.id);
    if (index != -1) {
      history[index] = attendanceToUpdate;
      final jsonList = history.map((e) => json.encode(e.toJson())).toList();
      await sharedPreferences.setStringList(cachedAttendance, jsonList);
    }
  }
}
