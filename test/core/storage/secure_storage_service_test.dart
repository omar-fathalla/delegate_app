import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/storage/secure_storage_service.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late SecureStorageService secureStorageService;
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    secureStorageService = SecureStorageService(prefs: mockSharedPreferences);
  });

  group('SecureStorageService', () {
    const tKey = 'test_key';
    const tPrefixedKey = 'secure_test_key';
    const tValue = 'test_value';

    group('write', () {
      test('should prepend secure_ prefix and call _prefs.setString', () async {
        // arrange
        when(() => mockSharedPreferences.setString(any(), any()))
            .thenAnswer((_) async => true);

        // act
        await secureStorageService.write(key: tKey, value: tValue);

        // assert
        verify(() => mockSharedPreferences.setString(tPrefixedKey, tValue)).called(1);
      });
    });

    group('read', () {
      test('should prepend secure_ prefix, call _prefs.getString, and return the string value when the key exists', () async {
        // arrange
        when(() => mockSharedPreferences.getString(any())).thenReturn(tValue);

        // act
        final result = await secureStorageService.read(key: tKey);

        // assert
        verify(() => mockSharedPreferences.getString(tPrefixedKey)).called(1);
        expect(result, tValue);
      });

      test('should return null when _prefs.getString returns null', () async {
        // arrange
        when(() => mockSharedPreferences.getString(any())).thenReturn(null);

        // act
        final result = await secureStorageService.read(key: tKey);

        // assert
        verify(() => mockSharedPreferences.getString(tPrefixedKey)).called(1);
        expect(result, isNull);
      });
    });

    group('delete', () {
      test('should prepend secure_ prefix and call _prefs.remove', () async {
        // arrange
        when(() => mockSharedPreferences.remove(any()))
            .thenAnswer((_) async => true);

        // act
        await secureStorageService.delete(key: tKey);

        // assert
        verify(() => mockSharedPreferences.remove(tPrefixedKey)).called(1);
      });
    });

    group('writeJson', () {
      const tMapValue = {'key': 'value'};
      const tJsonString = '{"key":"value"}';

      test('should encode the Map to a JSON string and call write', () async {
        // arrange
        when(() => mockSharedPreferences.setString(any(), any()))
            .thenAnswer((_) async => true);

        // act
        await secureStorageService.writeJson(key: tKey, value: tMapValue);

        // assert
        verify(() => mockSharedPreferences.setString(tPrefixedKey, tJsonString)).called(1);
      });

      test('should swallow exceptions when jsonEncode fails', () async {
        // arrange
        final unencodableMap = {'key': Object()}; // This will throw JsonUnsupportedObjectError during jsonEncode

        // act & assert
        // Should not throw any exception
        await expectLater(
          () => secureStorageService.writeJson(key: tKey, value: unencodableMap),
          returnsNormally,
        );
        // And should not call setString
        verifyNever(() => mockSharedPreferences.setString(any(), any()));
      });
    });

    group('readJson', () {
      const tJsonString = '{"key":"value"}';
      const tMapValue = {'key': 'value'};

      test('should decode valid JSON strings back to a Map', () async {
        // arrange
        when(() => mockSharedPreferences.getString(any())).thenReturn(tJsonString);

        // act
        final result = await secureStorageService.readJson(key: tKey);

        // assert
        verify(() => mockSharedPreferences.getString(tPrefixedKey)).called(1);
        expect(result, equals(tMapValue));
      });

      test('should return null if the raw string is null', () async {
        // arrange
        when(() => mockSharedPreferences.getString(any())).thenReturn(null);

        // act
        final result = await secureStorageService.readJson(key: tKey);

        // assert
        verify(() => mockSharedPreferences.getString(tPrefixedKey)).called(1);
        expect(result, isNull);
      });

      test('should return null and swallow exceptions when _prefs.getString returns invalid JSON', () async {
        // arrange
        const invalidJson = 'invalid-json';
        when(() => mockSharedPreferences.getString(any())).thenReturn(invalidJson);

        // act
        final result = await secureStorageService.readJson(key: tKey);

        // assert
        verify(() => mockSharedPreferences.getString(tPrefixedKey)).called(1);
        expect(result, isNull); // The FormatException should be caught and null returned
      });
    });

    group('clearAll', () {
      test('should call _prefs.getKeys(), filter keys starting with secure_, and call _prefs.remove() for each', () async {
        // arrange
        final allKeys = {'secure_key1', 'other_key', 'secure_key2', 'another_secure_key'};
        when(() => mockSharedPreferences.getKeys()).thenReturn(allKeys);
        when(() => mockSharedPreferences.remove(any()))
            .thenAnswer((_) async => true);

        // act
        await secureStorageService.clearAll();

        // assert
        verify(() => mockSharedPreferences.getKeys()).called(1);
        verify(() => mockSharedPreferences.remove('secure_key1')).called(1);
        verify(() => mockSharedPreferences.remove('secure_key2')).called(1);
        verifyNever(() => mockSharedPreferences.remove('other_key'));
        verifyNever(() => mockSharedPreferences.remove('another_secure_key')); // doesn't start with secure_
      });
    });
  });
}
