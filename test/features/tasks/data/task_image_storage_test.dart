import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/domain/task_proof_paths.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeFunctions extends Mock implements FirebaseFunctions {}

class _FakeCallable extends Mock implements HttpsCallable {}

class _FakeResult extends Fake implements HttpsCallableResult<dynamic> {
  _FakeResult(this.data);
  @override
  final dynamic data;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  test('pathFor uses the company folder and an exact N1-r file name', () {
    expect(
      TaskImageStorage.pathFor('coA', 'sup1', '171000'),
      'task_images/coA/sup1/task_sup1_171000.jpg',
    );
    expect(
      TaskImageStorage.fileNameFor('sup1', '171000'),
      'task_sup1_171000.jpg',
    );
    expect(
      TaskImageStorage.fileNameFor('sup1', '171000').contains('task_sup1_2_'),
      isFalse,
    );
  });

  test('hasImage is true for a path-only task and for a legacy url', () {
    TaskEntity base({String? url, String? path}) => TaskEntity(
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
      imageUrl: url,
      imagePath: path,
    );
    expect(
      base(path: 'task_images/c1/sup-1/task_sup-1_1.jpg').hasImage,
      isTrue,
    );
    expect(base(url: 'https://example.com/a.jpg').hasImage, isTrue);
    expect(base().hasImage, isFalse);
    expect(
      base(
        url: 'https://example.com/a.jpg',
        path: 'task_images/c1/sup-1/task_sup-1_1.jpg',
      ).copyWith(clearImageUrl: true).imageUrl,
      isNull,
    );
  });

  test(
    'fetcher calls getTaskImage with the path and task id, not a public URL',
    () async {
      final functions = _FakeFunctions();
      final callable = _FakeCallable();
      when(() => functions.httpsCallable('getTaskImage')).thenReturn(callable);
      when(() => callable.call(any())).thenAnswer((inv) async {
        final arg = inv.positionalArguments.first as Map;
        expect(arg['imagePath'], 'task_images/coA/sup1/task_sup1_1.jpg');
        expect(arg['taskId'], 't1');
        expect(arg['organizationId'], 'o1');
        expect(
          arg.values.every(
            (v) => v is! String || !v.toString().startsWith('http'),
          ),
          isTrue,
        );
        return _FakeResult({
          'contentType': 'image/jpeg',
          'data': base64Encode(Uint8List.fromList(const [1, 2, 3, 4])),
        });
      });

      final bytes = await TaskImageFetcher(functions: functions).load(
        imagePath: 'task_images/coA/sup1/task_sup1_1.jpg',
        taskId: 't1',
        organizationId: 'o1',
      );
      expect(bytes, Uint8List.fromList(const [1, 2, 3, 4]));
      verify(() => callable.call(any())).called(1);
    },
  );
  test('proof storage uses a distinct purpose and N1-r path', () {
    final storage = TaskImageStorage.proof();
    expect(storage.purpose, kTaskProofPurpose);
    expect(storage.rootPrefix, kTaskProofRoot);
    expect(storage.namePrefix, 'proof');
    expect(TaskImageFetcher.proof().callableName, 'getTaskProofImage');
  });
}
