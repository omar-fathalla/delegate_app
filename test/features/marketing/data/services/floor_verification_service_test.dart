import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/marketing/data/models/floor_verification_model.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCollection;
  late MockDocumentReference mockDocument;
  late SharedPreferences prefs;
  late FloorVerificationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference();
    mockDocument = MockDocumentReference();

    when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
    when(() => mockCollection.doc(any())).thenReturn(mockDocument);
    when(() => mockDocument.set(any(), any())).thenAnswer((_) async {});
    when(() => mockDocument.delete()).thenAnswer((_) async {});

    service = FloorVerificationService(
      prefs: prefs,
      firestore: mockFirestore,
    );
  });

  group('FloorVerificationItem Model', () {
    test('should correctly serialize to and deserialize from JSON', () {
      final now = DateTime(2026, 9, 26, 11, 25);
      final item = FloorVerificationItem(
        delegateId: 'del_123',
        branchName: 'فرع المعادي',
        date: '2026-09-26',
        status: 'verified',
        timestamp: now,
        verifiedBy: 'user_456',
        verifierName: 'مشرف الصالة',
      );

      final json = item.toJson();
      expect(json['delegateId'], 'del_123');
      expect(json['branchName'], 'فرع المعادي');
      expect(json['status'], 'verified');
      expect(json['verifiedBy'], 'user_456');

      final deserialized = FloorVerificationItem.fromJson(json);
      expect(deserialized.delegateId, item.delegateId);
      expect(deserialized.branchName, item.branchName);
      expect(deserialized.status, item.status);
      expect(deserialized.isVerified, isTrue);
      expect(deserialized.isMissing, isFalse);
    });

    test('isMissing should return true when status is missing', () {
      final item = FloorVerificationItem(
        delegateId: 'del_123',
        branchName: 'فرع المعادي',
        date: '2026-09-26',
        status: 'missing',
        timestamp: DateTime.now(),
        verifiedBy: 'user_456',
        verifierName: 'مشرف الصالة',
      );

      expect(item.isMissing, isTrue);
      expect(item.isVerified, isFalse);
    });
  });

  group('FloorVerificationService Local Storage', () {
    test('saveVerification and getLocalVerifications should work with 0ms local read/write', () async {
      final date = DateTime(2026, 9, 26);
      final item = FloorVerificationItem(
        delegateId: 'del_999',
        branchName: 'فرع التجمع',
        date: '2026-09-26',
        status: 'verified',
        timestamp: DateTime.now(),
        verifiedBy: 'sup_1',
        verifierName: 'أحمد المشرف',
      );

      // Verify initial empty
      final initialMap = service.getLocalVerifications(date);
      expect(initialMap.isEmpty, isTrue);

      // Save item
      await service.saveVerification(item: item);

      // Retrieve item
      final afterMap = service.getLocalVerifications(date);
      expect(afterMap.length, 1);
      expect(afterMap['del_999']?.delegateId, 'del_999');
      expect(afterMap['del_999']?.isVerified, isTrue);
    });

    test('removeVerification should remove delegate from local store', () async {
      final date = DateTime(2026, 9, 26);
      final item = FloorVerificationItem(
        delegateId: 'del_888',
        branchName: 'فرع الدقي',
        date: '2026-09-26',
        status: 'verified',
        timestamp: DateTime.now(),
        verifiedBy: 'sup_1',
        verifierName: 'أحمد المشرف',
      );

      await service.saveVerification(item: item);
      expect(service.getLocalVerifications(date).containsKey('del_888'), isTrue);

      await service.removeVerification(
        dateStr: '2026-09-26',
        branchName: 'فرع الدقي',
        delegateId: 'del_888',
      );

      expect(service.getLocalVerifications(date).containsKey('del_888'), isFalse);
    });
  });
}
