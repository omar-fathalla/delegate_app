import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tBranch = BranchModel(
    id: 'b1',
    branchName: 'الفرع الرئيسي',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 150.0,
  );

  group('BranchModel.fromMap', () {
    test('parses nested location format', () {
      final map = {
        'branchName': 'الفرع الرئيسي',
        'location': {'latitude': 30.0444, 'longitude': 31.2357},
        'geofenceRadius': 150.0,
      };

      final result = BranchModel.fromMap(map, id: 'b1');

      expect(result.branchName, 'الفرع الرئيسي');
      expect(result.latitude, 30.0444);
      expect(result.longitude, 31.2357);
      expect(result.geofenceRadius, 150.0);
      expect(result.id, 'b1');
    });

    test('parses top-level latitude/longitude (backwards compat)', () {
      final map = {
        'branchName': 'فرع قديم',
        'latitude': 29.9765,
        'longitude': 31.1313,
        'geofenceRadius': 200.0,
      };

      final result = BranchModel.fromMap(map, id: 'b2');

      expect(result.latitude, 29.9765);
      expect(result.longitude, 31.1313);
    });

    test('uses default values when fields are missing', () {
      final result = BranchModel.fromMap({});

      expect(result.branchName, '');
      expect(result.latitude, 0.0);
      expect(result.longitude, 0.0);
      expect(result.geofenceRadius, 100.0);
    });

    test('handles int values for coordinates', () {
      final map = {
        'branchName': 'فرع',
        'location': {'latitude': 30, 'longitude': 31},
        'geofenceRadius': 100,
      };

      final result = BranchModel.fromMap(map);

      expect(result.latitude, 30.0);
      expect(result.longitude, 31.0);
      expect(result.geofenceRadius, 100.0);
    });
  });

  group('BranchModel.toMap', () {
    test('serializes with nested location format', () {
      final map = tBranch.toMap();

      expect(map['branchName'], 'الفرع الرئيسي');
      expect((map['location'] as Map)['latitude'], 30.0444);
      expect((map['location'] as Map)['longitude'], 31.2357);
      expect(map['geofenceRadius'], 150.0);
    });

    test('does not include id in toMap output', () {
      final map = tBranch.toMap();
      expect(map.containsKey('id'), isFalse);
    });
  });

  group('Branch entity equality', () {
    test('two branches with same props are equal', () {
      const branch1 = BranchModel(
        id: 'b1',
        branchName: 'Test',
        latitude: 1.0,
        longitude: 2.0,
        geofenceRadius: 100.0,
      );
      const branch2 = BranchModel(
        id: 'b1',
        branchName: 'Test',
        latitude: 1.0,
        longitude: 2.0,
        geofenceRadius: 100.0,
      );

      expect(branch1, equals(branch2));
    });
  });
}
