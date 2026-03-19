import 'dart:convert';

import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AuthLocalDataSourceImpl dataSource;
  late SharedPreferences sharedPreferences;

  final tDelegateModel = DelegateModel(
    uid: 'u1',
    firstName: 'أحمد',
    middleName: 'محمد',
    lastName: 'علي',
    fullName: 'أحمد محمد علي',
    nationalityID: '12345678901234',
    motherName: 'منى',
    city: 'القاهرة',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1995, 1, 1),
    organizationUID: 'org1',
    organizationName: 'منظمة تسهيل',
    companyUID: 'comp1',
    companyName: 'شركة تسهيل',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-001',
    allReceiptCodes: const [],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    dataSource =
        AuthLocalDataSourceImpl(sharedPreferences: sharedPreferences);
  });

  group('cacheDelegateData', () {
    test('should save delegate data to SharedPreferences', () async {
      await dataSource.cacheDelegateData(tDelegateModel);

      final savedString = sharedPreferences.getString(cachedDelegateKey);
      expect(savedString, isNotNull);

      final decoded = json.decode(savedString!) as Map<String, dynamic>;
      expect(decoded['uid'], 'u1');
      expect(decoded['firstName'], 'أحمد');
    });
  });

  group('getCachedDelegateData', () {
    test('should return null when no cached data exists', () {
      final result = dataSource.getCachedDelegateData();
      expect(result, isNull);
    });

    test('should return DelegateModel when cached data exists', () async {
      await dataSource.cacheDelegateData(tDelegateModel);

      final result = dataSource.getCachedDelegateData();

      expect(result, isNotNull);
      expect(result!.uid, 'u1');
      expect(result.firstName, 'أحمد');
      expect(result.phoneNumber, '01000000000');
    });
  });

  group('clearCachedData', () {
    test('should remove cached data from SharedPreferences', () async {
      await dataSource.cacheDelegateData(tDelegateModel);
      expect(sharedPreferences.getString(cachedDelegateKey), isNotNull);

      await dataSource.clearCachedData();

      expect(sharedPreferences.getString(cachedDelegateKey), isNull);
    });
  });
}
