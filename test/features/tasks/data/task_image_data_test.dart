import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockRef extends Mock implements Reference {}

void main() {
  late FakeFirebaseFirestore db;
  late _MockStorage storage;
  late _MockRef ref;
  late TaskRemoteDataSourceImpl ds;

  final base = TaskModel(
    uid: 't1',
    title: 'T',
    description: 'D',
    priority: TaskPriority.low,
    status: TaskStatus.pending,
    assignedTo: 'del-1',
    assignedToName: 'Del',
    companyId: 'c1',
    createdBy: 'sup-1',
    createdByName: 'Sup',
    dueDate: DateTime(2026, 11, 3),
    createdAt: DateTime(2026, 11, 2),
    imageUrl: 'https://x/a.jpg',
    imagePath: 'organizations/o1/task_images/sup-1/a.jpg',
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    storage = _MockStorage();
    ref = _MockRef();
    when(() => storage.ref(any())).thenReturn(ref);
    when(() => ref.delete()).thenAnswer((_) async {});
    ds = TaskRemoteDataSourceImpl(firestore: db, storage: storage);
  });

  test(
    'model round-trips image and edited fields; omits them when null',
    () async {
      final edited = TaskModel.fromEntity(
        base.copyWith(editedAt: DateTime(2026, 11, 2, 10)),
      );
      await db.doc('organizations/o1/tasks/t1').set(edited.toFirestore());
      final back = TaskModel.fromFirestore(
        await db.doc('organizations/o1/tasks/t1').get(),
      );
      expect(back.imageUrl, base.imageUrl);
      expect(back.imagePath, base.imagePath);
      expect(back.isEdited, isTrue);
      final plain = TaskModel.fromEntity(
        base.copyWith(clearImage: true),
      ).toFirestore();
      expect(plain.containsKey('imageUrl'), isFalse);
      expect(plain.containsKey('editedAt'), isFalse);
    },
  );

  test('createTask stores the image', () async {
    final created = await ds.createTask('o1', base);
    final snap = await db.doc('organizations/o1/tasks/${created.uid}').get();
    expect(snap.data()!['imagePath'], base.imagePath);
  });

  test(
    'sender edit that removes the image clears fields and deletes the file',
    () async {
      await db.doc('organizations/o1/tasks/t1').set(base.toFirestore());
      final edited = base.copyWith(
        clearImage: true,
        editedAt: DateTime.now(),
        description: 'D2',
      );
      await ds.updateTask('o1', TaskModel.fromEntity(edited));
      final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
      expect(data.containsKey('imageUrl'), isFalse);
      expect(data['description'], 'D2');
      expect(data['editedAt'], isA<Timestamp>());
      verify(() => storage.ref(base.imagePath!)).called(1);
      verify(() => ref.delete()).called(1);
    },
  );

  test('delegate status update keeps the image and deletes nothing', () async {
    await db.doc('organizations/o1/tasks/t1').set(base.toFirestore());
    await ds.updateTask(
      'o1',
      TaskModel.fromEntity(base.copyWith(status: TaskStatus.completed)),
    );
    final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
    expect(data['imageUrl'], base.imageUrl);
    verifyNever(() => ref.delete());
  });

  test('deleteTask removes the doc and its image', () async {
    await db.doc('organizations/o1/tasks/t1').set(base.toFirestore());
    await ds.deleteTask('o1', 't1');
    expect((await db.doc('organizations/o1/tasks/t1').get()).exists, isFalse);
    verify(() => ref.delete()).called(1);
  });

  test(
    'title-only sender edit keeps imagePath when imageUrl is absent',
    () async {
      const path = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      final phase2 = TaskModel.fromEntity(
        base.copyWith(imagePath: path, clearImageUrl: true),
      );
      await db.doc('organizations/o1/tasks/t1').set(phase2.toFirestore());
      await ds.updateTask(
        'o1',
        TaskModel.fromEntity(
          phase2.copyWith(title: 'T2', editedAt: DateTime(2026, 11, 12, 8)),
        ),
      );
      final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
      expect(data['imagePath'], path);
      expect(data.containsKey('imageUrl'), isFalse);
      expect(data['title'], 'T2');
      verifyNever(() => ref.delete());
    },
  );

  test(
    'replace + save links the new image and deletes only the old file',
    () async {
      const oldPath = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      const newPath = 'task_images/c1/sup-1/task_sup-1_2.jpg';
      final phase2 = TaskModel.fromEntity(
        base.copyWith(imagePath: oldPath, clearImageUrl: true),
      );
      await db.doc('organizations/o1/tasks/t1').set(phase2.toFirestore());
      await ds.updateTask(
        'o1',
        TaskModel.fromEntity(
          phase2.copyWith(
            imagePath: newPath,
            editedAt: DateTime(2026, 11, 12, 8),
          ),
        ),
      );
      final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
      expect(data['imagePath'], newPath);
      expect(data.containsKey('imageUrl'), isFalse);
      verify(() => storage.ref(oldPath)).called(1);
      verify(() => ref.delete()).called(1);
      verifyNever(() => storage.ref(newPath));
    },
  );

  test(
    'explicit remove + save clears imagePath when imageUrl was already absent',
    () async {
      const path = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      final phase2 = TaskModel.fromEntity(
        base.copyWith(imagePath: path, clearImageUrl: true),
      );
      await db.doc('organizations/o1/tasks/t1').set(phase2.toFirestore());
      await ds.updateTask(
        'o1',
        TaskModel.fromEntity(
          phase2.copyWith(
            clearImage: true,
            editedAt: DateTime(2026, 11, 12, 8),
          ),
        ),
      );
      final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
      expect(data.containsKey('imagePath'), isFalse);
      expect(data.containsKey('imageUrl'), isFalse);
      verify(() => storage.ref(path)).called(1);
      verify(() => ref.delete()).called(1);
    },
  );

  test(
    'createTask stores up to 3 imagePaths and keeps imagePath as the first',
    () async {
      const paths = [
        'task_images/c1/sup-1/task_sup-1_1.jpg',
        'task_images/c1/sup-1/task_sup-1_2.jpg',
        'task_images/c1/sup-1/task_sup-1_3.jpg',
      ];
      final created = await ds.createTask(
        'o1',
        TaskModel.fromEntity(
          base.copyWith(
            imagePath: paths.first,
            imagePaths: paths,
            clearImageUrl: true,
          ),
        ),
      );
      final data = (await db.doc('organizations/o1/tasks/${created.uid}').get())
          .data()!;
      expect(data['imagePath'], paths.first);
      expect(data['imagePaths'], paths);
      expect(data.containsKey('imageUrl'), isFalse);
      final back = TaskModel.fromFirestore(
        await db.doc('organizations/o1/tasks/${created.uid}').get(),
      );
      expect(back.resolvedImagePaths, paths);
    },
  );

  test(
    'legacy single imagePath still loads when imagePaths is absent',
    () async {
      const path = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      await db.doc('organizations/o1/tasks/t1').set({
        ...TaskModel.fromEntity(base.copyWith(clearImage: true)).toFirestore(),
        'imagePath': path,
      });
      final back = TaskModel.fromFirestore(
        await db.doc('organizations/o1/tasks/t1').get(),
      );
      expect(back.imagePath, path);
      expect(back.resolvedImagePaths, [path]);
      expect(back.hasImage, isTrue);
    },
  );

  test('title-only edit keeps all images when imageUrl is absent', () async {
    const paths = [
      'task_images/c1/sup-1/task_sup-1_1.jpg',
      'task_images/c1/sup-1/task_sup-1_2.jpg',
    ];
    final phase3 = TaskModel.fromEntity(
      base.copyWith(
        imagePath: paths.first,
        imagePaths: paths,
        clearImageUrl: true,
      ),
    );
    await db.doc('organizations/o1/tasks/t1').set(phase3.toFirestore());
    await ds.updateTask(
      'o1',
      TaskModel.fromEntity(
        phase3.copyWith(title: 'T2', editedAt: DateTime(2026, 11, 12, 9)),
      ),
    );
    final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
    expect(data['imagePath'], paths.first);
    expect(data['imagePaths'], paths);
    expect(data['title'], 'T2');
    verifyNever(() => ref.delete());
  });

  test(
    'replace + save of one of two images links the new file and deletes only the old one',
    () async {
      const kept = 'task_images/c1/sup-1/task_sup-1_1.jpg';
      const oldPath = 'task_images/c1/sup-1/task_sup-1_2.jpg';
      const newPath = 'task_images/c1/sup-1/task_sup-1_3.jpg';
      final before = TaskModel.fromEntity(
        base.copyWith(
          imagePath: kept,
          imagePaths: [kept, oldPath],
          clearImageUrl: true,
        ),
      );
      await db.doc('organizations/o1/tasks/t1').set(before.toFirestore());
      await ds.updateTask(
        'o1',
        TaskModel.fromEntity(
          before.copyWith(
            imagePath: kept,
            imagePaths: [kept, newPath],
            editedAt: DateTime(2026, 11, 12, 9),
          ),
        ),
      );
      final data = (await db.doc('organizations/o1/tasks/t1').get()).data()!;
      expect(data['imagePath'], kept);
      expect(data['imagePaths'], [kept, newPath]);
      verify(() => storage.ref(oldPath)).called(1);
      verify(() => ref.delete()).called(1);
      verifyNever(() => storage.ref(kept));
      verifyNever(() => storage.ref(newPath));
    },
  );
}
