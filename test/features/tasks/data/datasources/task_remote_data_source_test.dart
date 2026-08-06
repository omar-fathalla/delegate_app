import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late TaskRemoteDataSourceImpl dataSource;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = TaskRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  final tTaskModel = TaskModel(
    uid: 'test_task_1', // UID is ignored during creation as it generates a new one, but we can set it for updating
    title: 'Test Task',
    description: 'Description',
    priority: TaskPriority.high,
    status: TaskStatus.pending,
    assignedTo: 'delegate123',
    assignedToName: 'Delegate',
    companyId: 'company123',
    createdBy: 'admin123',
    createdByName: 'Admin',
    dueDate: DateTime(2023, 1, 2),
    createdAt: DateTime(2023, 1, 1),
  );

  group('createTask', () {
    test('should add task to firestore and return model with generated ID', () async {
      // Act
      final result = await dataSource.createTask('org123', tTaskModel);

      // Assert
      expect(result.title, equals(tTaskModel.title));
      expect(result.uid, isNotEmpty);
      
      final doc = await fakeFirestore
          .collection('organizations')
          .doc('org123')
          .collection('tasks')
          .doc(result.uid)
          .get();
          
      expect(doc.exists, isTrue);
      expect(doc.data()!['title'], equals('Test Task'));
    });
  });

  group('updateTaskStatus', () {
    test('should update status, notes, and completed fields', () async {
      // Arrange
      final docRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks').doc('task_to_update');
      await docRef.set(tTaskModel.toFirestore());

      // Act
      await dataSource.updateTaskStatus(
        'org123',
        'task_to_update',
        TaskStatus.completed,
        notes: 'Done',
        completedBy: 'delegate123',
      );

      // Assert
      final doc = await docRef.get();
      expect(doc.data()!['status'], equals('completed'));
      expect(doc.data()!['notes'], equals('Done'));
      expect(doc.data()!['completedBy'], equals('delegate123'));
      expect(doc.data()!['completedAt'], isNotNull);
    });
  });

  group('getAdminTasks', () {
    test('should return tasks ordered by createdAt for a company', () async {
      // Arrange
      final colRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks');
      await colRef.add({...tTaskModel.toFirestore(), 'createdAt': Timestamp.fromDate(DateTime(2023, 1, 1))});
      await colRef.add({...tTaskModel.toFirestore(), 'createdAt': Timestamp.fromDate(DateTime(2023, 1, 2))});

      // Act
      final result = await dataSource.getAdminTasks('org123', 'company123');

      // Assert
      expect(result.length, equals(2));
      // Should be descending order
      expect(result[0].createdAt.isAfter(result[1].createdAt), isTrue);
    });

    test('should filter by status if provided', () async {
      // Arrange
      final colRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks');
      await colRef.add({...tTaskModel.toFirestore(), 'status': 'pending'});
      await colRef.add({...tTaskModel.toFirestore(), 'status': 'completed'});

      // Act
      final result = await dataSource.getAdminTasks('org123', 'company123', status: TaskStatus.completed);

      // Assert
      expect(result.length, equals(1));
      expect(result.first.status, equals(TaskStatus.completed));
    });
  });

  group('getDelegateTasks', () {
    test('should return tasks assigned to delegate or all/branches for a company', () async {
      // Arrange
      final colRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks');
      await colRef.add({...tTaskModel.toFirestore(), 'assignedTo': 'delegate123'});
      await colRef.add({...tTaskModel.toFirestore(), 'assignedTo': 'all'});
      await colRef.add({...tTaskModel.toFirestore(), 'assignedTo': 'other_delegate'}); // Shouldn't be returned

      // Act
      final result = await dataSource.getDelegateTasks('org123', 'delegate123', 'company123');

      // Assert
      expect(result.length, equals(2));
    });
  });

  group('updateTask', () {
    test('should update all fields of a task', () async {
      // Arrange
      final docRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks').doc('task_to_edit');
      await docRef.set(tTaskModel.toFirestore());
      
      final updatedModel = TaskModel(
        uid: 'task_to_edit',
        title: 'Updated Title',
        description: 'Updated Desc',
        priority: TaskPriority.low,
        status: TaskStatus.inProgress,
        assignedTo: 'delegate123',
        assignedToName: 'Delegate',
        companyId: 'company123',
        createdBy: 'admin123',
        createdByName: 'Admin',
        dueDate: DateTime(2023, 1, 2),
        createdAt: DateTime(2023, 1, 1),
      );

      // Act
      await dataSource.updateTask('org123', updatedModel);

      // Assert
      final doc = await docRef.get();
      expect(doc.data()!['title'], equals('Updated Title'));
      expect(doc.data()!['status'], equals('inProgress'));
    });
  });

  group('deleteTask', () {
    test('should delete task document from firestore', () async {
      // Arrange
      final docRef = fakeFirestore.collection('organizations').doc('org123').collection('tasks').doc('task_to_delete');
      await docRef.set(tTaskModel.toFirestore());

      // Act
      await dataSource.deleteTask('org123', 'task_to_delete');

      // Assert
      final doc = await docRef.get();
      expect(doc.exists, isFalse);
    });
  });
}
