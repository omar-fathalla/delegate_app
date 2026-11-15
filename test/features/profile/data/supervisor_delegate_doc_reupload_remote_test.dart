import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/profile/data/datasources/supervisor_delegate_doc_reupload_remote.dart';
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
    registerFallbackValue(File.fromRawPath(Uint8List.fromList([0, 1, 2, 3])));
  });

  test('delegateDocumentStoragePath matches profile_screen layout', () {
    expect(
      delegateDocumentStoragePath(
        delegateUid: 'd1',
        docType: 'nationalIdFront',
        timestampMs: 171000,
      ),
      'delegate_documents/d1/nationalIdFront_171000.jpg',
    );
  });

  test('replaceWithFile calls intent, upload, then supervisor callable', () async {
    final functions = _FakeFunctions();
    final intentCallable = _FakeCallable();
    final reuploadCallable = _FakeCallable();
    when(
      () => functions.httpsCallable('ensureStorageUploadIntent'),
    ).thenReturn(intentCallable);
    when(
      () => functions.httpsCallable('supervisorReuploadDelegateDocument'),
    ).thenReturn(reuploadCallable);

    Map? intentPayload;
    Map? reuploadPayload;
    when(() => intentCallable.call(any())).thenAnswer((inv) async {
      intentPayload = inv.positionalArguments.first as Map;
      return _FakeResult({'ok': true});
    });
    when(() => reuploadCallable.call(any())).thenAnswer((inv) async {
      reuploadPayload = inv.positionalArguments.first as Map;
      return _FakeResult({'status': 'pending'});
    });

    final file = File.fromRawPath(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
    var uploadPath = '';
    await SupervisorDelegateDocReuploadRemote(functions: functions).replaceWithFile(
      uid: 'd1',
      organizationUID: 'o1',
      companyUID: 'c1',
      docType: 'personalPhoto',
      file: file,
      ensureIntent: ({required folderId, required companyUID, functions}) async {
        expect(folderId, 'd1');
        expect(companyUID, 'c1');
        return null;
      },
      uploadFile: (path, f) async {
        uploadPath = path;
        expect(f.path, file.path);
        return 'https://cdn.example/new.jpg';
      },
    );

    expect(intentPayload, isNull);
    expect(uploadPath, startsWith('delegate_documents/d1/personalPhoto_'));
    expect(reuploadPayload!['uid'], 'd1');
    expect(reuploadPayload!['organizationUID'], 'o1');
    expect(reuploadPayload!['companyUID'], 'c1');
    expect(reuploadPayload!['docType'], 'personalPhoto');
    expect(reuploadPayload!['newUrl'], 'https://cdn.example/new.jpg');
    verify(() => reuploadCallable.call(any())).called(1);
  });

  test('replaceWithFile surfaces intent errors before upload', () async {
    final functions = _FakeFunctions();
    final reuploadCallable = _FakeCallable();
    when(
      () => functions.httpsCallable('supervisorReuploadDelegateDocument'),
    ).thenReturn(reuploadCallable);

    var uploadCalled = false;
    expect(
      () => SupervisorDelegateDocReuploadRemote(functions: functions).replaceWithFile(
        uid: 'd1',
        organizationUID: 'o1',
        companyUID: 'c1',
        docType: 'personalPhoto',
        file: File.fromRawPath(Uint8List.fromList([1])),
        ensureIntent: ({required folderId, required companyUID, functions}) async {
          return 'لا يمكن رفع المستندات لمجلد يخص شركة أخرى.';
        },
        uploadFile: (path, f) async {
          uploadCalled = true;
          return 'https://cdn.example/x.jpg';
        },
      ),
      throwsA(
        isA<SupervisorDocReuploadException>().having(
          (e) => e.message,
          'message',
          contains('شركة أخرى'),
        ),
      ),
    );
    expect(uploadCalled, isFalse);
    verifyNever(() => reuploadCallable.call(any()));
  });

  test('reviewDocument calls privilegedReuploadDelegateDocument with approve', () async {
    final functions = _FakeFunctions();
    final privilegedCallable = _FakeCallable();
    when(
      () => functions.httpsCallable('privilegedReuploadDelegateDocument'),
    ).thenReturn(privilegedCallable);

    Map? payload;
    when(() => privilegedCallable.call(any())).thenAnswer((inv) async {
      payload = inv.positionalArguments.first as Map;
      return _FakeResult({'documentStatus': 'approved'});
    });

    await PrivilegedDelegateDocReuploadRemote(functions: functions).reviewDocument(
      uid: 'd1',
      organizationUID: 'o1',
      companyUID: 'c1',
      docType: 'personalPhoto',
      approve: true,
    );

    expect(payload!['approve'], true);
    expect(payload!.containsKey('newUrl'), false);
    verify(() => privilegedCallable.call(any())).called(1);
  });

  test('privileged replaceWithFile calls privilegedReuploadDelegateDocument', () async {
    final functions = _FakeFunctions();
    final privilegedCallable = _FakeCallable();
    when(
      () => functions.httpsCallable('privilegedReuploadDelegateDocument'),
    ).thenReturn(privilegedCallable);

    Map? payload;
    when(() => privilegedCallable.call(any())).thenAnswer((inv) async {
      payload = inv.positionalArguments.first as Map;
      return _FakeResult({'documentStatus': 'approved'});
    });

    final file = File.fromRawPath(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
    await PrivilegedDelegateDocReuploadRemote(functions: functions).replaceWithFile(
      uid: 'd1',
      organizationUID: 'o1',
      companyUID: 'c1',
      docType: 'nationalIdFront',
      file: file,
      ensureIntent: ({required folderId, required companyUID, functions}) async => null,
      uploadFile: (path, f) async => 'https://cdn.example/id.jpg',
    );

    expect(payload!['uid'], 'd1');
    expect(payload!['docType'], 'nationalIdFront');
    expect(payload!['newUrl'], 'https://cdn.example/id.jpg');
    verify(() => privilegedCallable.call(any())).called(1);
  });

  test('supervisorDocReplaceErrorMessage maps storage unauthorized', () {
    expect(
      supervisorDocReplaceErrorMessage(
        SupervisorDocReuploadException('تعذر تجهيز المجلد'),
      ),
      'تعذر تجهيز المجلد',
    );
  });
}