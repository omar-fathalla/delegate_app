import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  final tDate = DateTime(2023, 1, 1);
  final tPenaltyModel = PenaltyModel(
    penaltyId: 'test_id',
    companyId: 'company_123',
    companyName: 'Test Company',
    createdById: 'admin_123',
    createdByName: 'Admin Name',
    title: 'Test Penalty',
    category: ViolationCategory.dataMissing,
    incidentDescription: 'Missing data in form',
    fineAmount: 50.0,
    currency: 'EGP',
    status: PenaltyStatus.issued,
    evidenceFiles: const [
      EvidenceFile(
        fileUrl: 'http://test.com/file.jpg',
        fileType: 'IMAGE',
        fileName: 'file.jpg',
      ),
    ],
    createdAt: tDate,
    updatedAt: tDate,
  );

  test('should be a subclass of PenaltyEntity', () {
    expect(tPenaltyModel, isA<PenaltyEntity>());
  });

  group('fromFirestore', () {
    test('should return a valid model when creating from DocumentSnapshot', () {
      // Arrange
      final mockDocumentSnapshot = MockDocumentSnapshot();
      when(() => mockDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockDocumentSnapshot.data()).thenReturn({
        'companyId': 'company_123',
        'companyName': 'Test Company',
        'createdById': 'admin_123',
        'createdByName': 'Admin Name',
        'title': 'Test Penalty',
        'category': 'DATA_MISSING',
        'incidentDescription': 'Missing data in form',
        'fineAmount': 50.0,
        'currency': 'EGP',
        'status': 'ISSUED',
        'evidenceFiles': [
          {
            'fileUrl': 'http://test.com/file.jpg',
            'fileType': 'IMAGE',
            'fileName': 'file.jpg',
          }
        ],
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      // Act
      final result = PenaltyModel.fromFirestore(mockDocumentSnapshot);

      // Assert
      expect(result, equals(tPenaltyModel));
    });
  });

  group('toJson', () {
    test('should return a JSON map containing the proper data', () {
      // Act
      final result = tPenaltyModel.toJson();

      // Assert
      final expectedMap = {
        'penaltyId': 'test_id',
        'companyId': 'company_123',
        'companyName': 'Test Company',
        'createdById': 'admin_123',
        'createdByName': 'Admin Name',
        'title': 'Test Penalty',
        'category': 'DATA_MISSING',
        'incidentDescription': 'Missing data in form',
        'fineAmount': 50.0,
        'currency': 'EGP',
        'status': 'ISSUED',
        'evidenceFiles': [
          {
            'fileUrl': 'http://test.com/file.jpg',
            'fileType': 'IMAGE',
            'fileName': 'file.jpg',
          }
        ],
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      };

      expect(result, equals(expectedMap));
    });
  });

  group('fromEntity', () {
    test('should return a valid model when creating from PenaltyEntity', () {
      // Arrange
      final entity = PenaltyEntity(
        penaltyId: 'test_id',
        companyId: 'company_123',
        companyName: 'Test Company',
        createdById: 'admin_123',
        createdByName: 'Admin Name',
        title: 'Test Penalty',
        category: ViolationCategory.dataMissing,
        incidentDescription: 'Missing data in form',
        fineAmount: 50.0,
        createdAt: tDate,
        updatedAt: tDate,
        evidenceFiles: const [
          EvidenceFile(
            fileUrl: 'http://test.com/file.jpg',
            fileType: 'IMAGE',
            fileName: 'file.jpg',
          ),
        ],
      );

      // Act
      final result = PenaltyModel.fromEntity(entity);

      // Assert
      expect(result, equals(tPenaltyModel));
    });
  });
}
