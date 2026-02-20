import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AttendanceOfflineQueue {
  Future<void> addToQueue(Map<String, dynamic> action);
  Future<List<Map<String, dynamic>>> getQueue();
  Future<void> clearQueue();
}

const String cachedOfflineQueue = 'cachedOfflineAttendanceQueue';

class AttendanceOfflineQueueImpl implements AttendanceOfflineQueue {
  final SharedPreferences sharedPreferences;

  AttendanceOfflineQueueImpl({required this.sharedPreferences});

  @override
  Future<void> addToQueue(Map<String, dynamic> action) async {
    final queue = await getQueue();
    queue.add(action);
    final jsonList = queue.map((e) => json.encode(e)).toList();
    await sharedPreferences.setStringList(cachedOfflineQueue, jsonList);
  }

  @override
  Future<List<Map<String, dynamic>>> getQueue() async {
    final jsonList = sharedPreferences.getStringList(cachedOfflineQueue);
    if (jsonList != null && jsonList.isNotEmpty) {
      return jsonList
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList();
    }
    return [];
  }

  @override
  Future<void> clearQueue() async {
    await sharedPreferences.remove(cachedOfflineQueue);
  }
}
