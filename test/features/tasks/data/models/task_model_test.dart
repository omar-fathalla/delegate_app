import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  final tCreatedAt = DateTime(2023, 1, 1);
  final tDueDate = DateTime(2023, 1, 2);
  final tCompletedAt = DateTime(2023, 1, 3);
  
  final tTaskModel = TaskModel(
    uid: 'task123',
    title: 'Test Task',
    description: 'Task description',
    priority: TaskPriority.high,
    status: TaskStatus.completed,
    assignedTo: 'delegate456',
    assignedToName: 'Delegate Name',
    companyId: 'company789',
    createdBy: 'admin123',
    createdByName: 'Admin Name',
    dueDate: tDueDate,
    createdAt: tCreatedAt,
    completedAt: tCompletedAt,
    completedBy: 'delegate456',
    notes: 'Task completed successfully',
  );

  test('should be a subclass of TaskEntity', () {
    expect(tTaskModel, isA<TaskEntity>());
  });

  group('fromEntity', () {
    test('should return a valid model from entity', () {
      final tTaskEntity = TaskEntity(
        uid: 'task123',
        title: 'Test Task',
        description: 'Task description',
        priority: TaskPriority.high,
        status: TaskStatus.completed,
        assignedTo: 'delegate456',
        assignedToName: 'Delegate Name',
        companyId: 'company789',
        createdBy: 'admin123',
        createdByName: 'Admin Name',
        dueDate: tDueDate,
        createdAt: tCreatedAt,
        completedAt: tCompletedAt,
        completedBy: 'delegate456',
        notes: 'Task completed successfully',
      );

      final result = TaskModel.fromEntity(tTaskEntity);
      
      expect(result, equals(tTaskModel));
    });
  });

  group('fromFirestore', () {
    test('should return a valid model when creating from DocumentSnapshot', () {
      final mockDocumentSnapshot = MockDocumentSnapshot();
      when(() => mockDocumentSnapshot.id).thenReturn('task123');
      when(() => mockDocumentSnapshot.data()).thenReturn({
        'title': 'Test Task',
        'description': 'Task description',
        'priority': 'high',
        'status': 'completed',
        'assignedTo': 'delegate456',
        'assignedToName': 'Delegate Name',
        'companyId': 'company789',
        'createdBy': 'admin123',
        'createdByName': 'Admin Name',
        'dueDate': Timestamp.fromDate(tDueDate),
        'createdAt': Timestamp.fromDate(tCreatedAt),
        'completedAt': Timestamp.fromDate(tCompletedAt),
        'completedBy': 'delegate456',
        'notes': 'Task completed successfully',
      });

      final result = TaskModel.fromFirestore(mockDocumentSnapshot);

      expect(result, equals(tTaskModel));
    });
  });

  group('toFirestore', () {
    test('should return a JSON map containing the proper data', () {
      final result = tTaskModel.toFirestore();
      
      final expectedMap = {
        'title': 'Test Task',
        'description': 'Task description',
        'priority': 'high',
        'status': 'completed',
        'assignedTo': 'delegate456',
        'assignedToName': 'Delegate Name',
        'companyId': 'company789',
        'createdBy': 'admin123',
        'createdByName': 'Admin Name',
        'dueDate': Timestamp.fromDate(tDueDate),
        'createdAt': Timestamp.fromDate(tCreatedAt),
        'completedAt': Timestamp.fromDate(tCompletedAt),
        'completedBy': 'delegate456',
        'notes': 'Task completed successfully',
      };
      
      expect(result, equals(expectedMap));
    });
  });
}
