import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockQuery<T> extends Mock implements Query<T> {}
class MockQuerySnapshot<T> extends Mock implements QuerySnapshot<T> {}
class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}
class MockDocumentSnapshot<T> extends Mock implements DocumentSnapshot<T> {}

void main() {
  late MockQuery<Map<String, dynamic>> mockQuery;
  late MockQuerySnapshot<Map<String, dynamic>> mockServerSnapshot;
  late MockQuerySnapshot<Map<String, dynamic>> mockCacheSnapshot;
  late MockDocumentReference<Map<String, dynamic>> mockDocRef;
  late MockDocumentSnapshot<Map<String, dynamic>> mockServerDocSnapshot;
  late MockDocumentSnapshot<Map<String, dynamic>> mockCacheDocSnapshot;

  setUpAll(() {
    registerFallbackValue(const GetOptions());
  });

  setUp(() {
    mockQuery = MockQuery<Map<String, dynamic>>();
    mockServerSnapshot = MockQuerySnapshot<Map<String, dynamic>>();
    mockCacheSnapshot = MockQuerySnapshot<Map<String, dynamic>>();

    mockDocRef = MockDocumentReference<Map<String, dynamic>>();
    mockServerDocSnapshot = MockDocumentSnapshot<Map<String, dynamic>>();
    mockCacheDocSnapshot = MockDocumentSnapshot<Map<String, dynamic>>();
  });

  group('FirestoreResilienceHelper - Query Tests', () {
    test('Solution 1: returns server data immediately when server query succeeds', () async {
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async => mockServerSnapshot);

      final result = await FirestoreResilienceHelper.getResilientQuery(
        mockQuery,
        timeout: const Duration(seconds: 2),
      );

      expect(result, equals(mockServerSnapshot));
      verify(() => mockQuery.get(const GetOptions(source: Source.server))).called(1);
      verifyNever(() => mockQuery.get(const GetOptions(source: Source.cache)));
    });

    test('Solution 2: falls back to local cache when server times out (Offline Mode)', () async {
      // Simulate server hanging or offline
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return mockServerSnapshot;
      });

      when(() => mockQuery.get(const GetOptions(source: Source.cache)))
          .thenAnswer((_) async => mockCacheSnapshot);

      final result = await FirestoreResilienceHelper.getResilientQuery(
        mockQuery,
        timeout: const Duration(milliseconds: 50), // Shorter timeout to trigger fallback
      );

      expect(result, equals(mockCacheSnapshot));
      verify(() => mockQuery.get(const GetOptions(source: Source.cache))).called(1);
    });

    test('Solution 3: falls back to local cache when server throws network exception', () async {
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

      when(() => mockQuery.get(const GetOptions(source: Source.cache)))
          .thenAnswer((_) async => mockCacheSnapshot);

      final result = await FirestoreResilienceHelper.getResilientQuery(
        mockQuery,
        timeout: const Duration(seconds: 2),
      );

      expect(result, equals(mockCacheSnapshot));
      verify(() => mockQuery.get(const GetOptions(source: Source.server))).called(1);
      verify(() => mockQuery.get(const GetOptions(source: Source.cache))).called(1);
    });

    test('Extension method .getResilient() delegates properly to helper', () async {
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async => mockServerSnapshot);

      final result = await mockQuery.getResilient();

      expect(result, equals(mockServerSnapshot));
    });
  });

  group('FirestoreResilienceHelper - Document Tests', () {
    test('returns server document when server query succeeds', () async {
      when(() => mockDocRef.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async => mockServerDocSnapshot);

      final result = await mockDocRef.getResilient();

      expect(result, equals(mockServerDocSnapshot));
      verify(() => mockDocRef.get(const GetOptions(source: Source.server))).called(1);
    });

    test('falls back to cache document when server throws', () async {
      when(() => mockDocRef.get(const GetOptions(source: Source.server)))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'));

      when(() => mockDocRef.get(const GetOptions(source: Source.cache)))
          .thenAnswer((_) async => mockCacheDocSnapshot);

      final result = await mockDocRef.getResilient();

      expect(result, equals(mockCacheDocSnapshot));
      verify(() => mockDocRef.get(const GetOptions(source: Source.cache))).called(1);
    });
  });

  group('FirestoreResilienceHelper - Real-time Streams', () {
    test('streamResilient includes metadata changes for instant cache emission', () {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      when(() => mockQuery.snapshots(includeMetadataChanges: true))
          .thenAnswer((_) => controller.stream);

      final stream = mockQuery.streamResilient();

      expect(stream, isNotNull);
      verify(() => mockQuery.snapshots(includeMetadataChanges: true)).called(1);
      controller.close();
    });
  });
}
