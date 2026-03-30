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
}
