import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AttendanceLocalDataSourceImpl dataSource;
  late SharedPreferences sharedPreferences;

  final tCheckInTime = DateTime(2024, 6, 15, 9, 0);

  final tAttendance1 = AttendanceModel(
    id: 'a1',
    userId: 'u1',
    organizationId: 'org1',
    checkInTime: tCheckInTime,
    latitude: 30.0444,
    longitude: 31.2357,
    branchName: 'الفرع الرئيسي',
  );

  final tAttendance2 = AttendanceModel(
    id: 'a2',
    userId: 'u1',
    organizationId: 'org1',
    checkInTime: tCheckInTime.add(const Duration(days: 1)),
    latitude: 30.0444,
    longitude: 31.2357,
    branchName: 'الفرع الرئيسي',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    dataSource = AttendanceLocalDataSourceImpl(
      sharedPreferences: sharedPreferences,
    );
  });

  group('cacheAttendance', () {
    test('should add attendance to SharedPreferences', () async {
      await dataSource.cacheAttendance(tAttendance1);

      final stored = sharedPreferences.getStringList(cachedAttendance);
      expect(stored, isNotNull);
      expect(stored!.length, 1);
    });

    test('should append to existing history', () async {
      await dataSource.cacheAttendance(tAttendance1);
      await dataSource.cacheAttendance(tAttendance2);

      final stored = sharedPreferences.getStringList(cachedAttendance);
      expect(stored!.length, 2);
    });
  });

  group('getLastAttendanceHistory', () {
    test('should return empty list when no data', () async {
      final result = await dataSource.getLastAttendanceHistory();
      expect(result, isEmpty);
    });

    test('should return cached attendance list', () async {
      await dataSource.cacheAttendance(tAttendance1);
      await dataSource.cacheAttendance(tAttendance2);

      final result = await dataSource.getLastAttendanceHistory();

      expect(result.length, 2);
      expect(result.first.id, 'a1');
      expect(result.last.id, 'a2');
    });
  });

  group('updateAttendance', () {
    test('should update existing attendance record', () async {
      await dataSource.cacheAttendance(tAttendance1);

      final updated = AttendanceModel(
        id: 'a1',
        userId: 'u1',
        organizationId: 'org1',
        checkInTime: tCheckInTime,
        checkOutTime: DateTime(2024, 6, 15, 17, 0),
        latitude: 30.0444,
        longitude: 31.2357,
        branchName: 'الفرع الرئيسي',
      );

      await dataSource.updateAttendance(updated);

      final result = await dataSource.getLastAttendanceHistory();
      expect(result.length, 1);
      expect(result.first.checkOutTime, isNotNull);
    });
  });

  group('overwriteHistory', () {
    test('should replace all cached data', () async {
      await dataSource.cacheAttendance(tAttendance1);
      await dataSource.cacheAttendance(tAttendance2);

      await dataSource.overwriteHistory([tAttendance1]);

      final result = await dataSource.getLastAttendanceHistory();
      expect(result.length, 1);
      expect(result.first.id, 'a1');
    });
  });

  group('user-scoped isolation and clearAttendanceCache', () {
    test('should isolate attendance cache per userId and organizationId', () async {
      final tAttendanceUser2 = AttendanceModel(
        id: 'a3',
        userId: 'u2',
        organizationId: 'org1',
        checkInTime: tCheckInTime,
        latitude: 30.0444,
        longitude: 31.2357,
        branchName: 'الفرع الرئيسي',
      );

      // Cache for user 1
      await dataSource.cacheAttendance(tAttendance1, 'org1', 'u1');
      // Cache for user 2
      await dataSource.cacheAttendance(tAttendanceUser2, 'org1', 'u2');

      // Retrieve for user 1
      final historyU1 = await dataSource.getLastAttendanceHistory('org1', 'u1');
      expect(historyU1.length, 1);
      expect(historyU1.first.id, 'a1');
      expect(historyU1.first.userId, 'u1');

      // Retrieve for user 2 - should never see user 1's records
      final historyU2 = await dataSource.getLastAttendanceHistory('org1', 'u2');
      expect(historyU2.length, 1);
      expect(historyU2.first.id, 'a3');
      expect(historyU2.first.userId, 'u2');
    });

    test('clearAttendanceCache should clear scoped cache for user', () async {
      await dataSource.cacheAttendance(tAttendance1, 'org1', 'u1');
      expect(await dataSource.getLastAttendanceHistory('org1', 'u1'), isNotEmpty);

      await dataSource.clearAttendanceCache('u1');
      expect(await dataSource.getLastAttendanceHistory('org1', 'u1'), isEmpty);
    });

    test('clearAttendanceCache with null userId should clear all attendance caches', () async {
      await dataSource.cacheAttendance(tAttendance1, 'org1', 'u1');
      await dataSource.cacheAttendance(tAttendance2, 'org2', 'u2');

      await dataSource.clearAttendanceCache();
      expect(await dataSource.getLastAttendanceHistory('org1', 'u1'), isEmpty);
      expect(await dataSource.getLastAttendanceHistory('org2', 'u2'), isEmpty);
    });
  });
}
