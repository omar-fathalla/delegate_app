import 'dart:typed_data';

import 'package:delegate_app/features/admin/data/repositories/delegate_profile_edit_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  group('stripCallableErrorSuffix', () {
    test('strips a raw [409] suffix (LOW)', () {
      expect(
        stripCallableErrorSuffix(
          'رقم الموبايل مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً. [409]',
        ),
        'رقم الموبايل مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً.',
      );
    });

    test('strips a trailing [already-exists] suffix', () {
      expect(stripCallableErrorSuffix('مكرر [already-exists]'), 'مكرر');
    });

    test('leaves a clean message unchanged', () {
      expect(stripCallableErrorSuffix('تعذر التحقق'), 'تعذر التحقق');
    });
  });

  group('saveDelegateProfileEdit H-1', () {
    test('saves name and phone when an image upload fails', () async {
      var editedName = '';
      var editedPhone = '';
      var photoUrl = 'set';
      final result = await saveDelegateProfileEdit(
        upload: ({required delegateUid, required kind, required file}) async {
          throw DelegateProfileEditException('storage down');
        },
        edit: ({
          String? fullName,
          String? phoneNumber,
          String? personalPhotoURL,
          String? nationalIdFrontUrl,
          String? nationalIdBackUrl,
        }) async {
          editedName = fullName ?? '';
          editedPhone = phoneNumber ?? '';
          photoUrl = personalPhotoURL ?? '';
        },
        delegateUid: 'd1',
        fullName: 'أحمد علي',
        phoneNumber: '01000000022',
        personalPhoto: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'p.jpg'),
      );
      expect(result.saved, isTrue);
      expect(result.imagesFailed, isTrue);
      expect(editedName, 'أحمد علي');
      expect(editedPhone, '01000000022');
      expect(photoUrl, isEmpty);
      expect(result.message, contains('تم حفظ الاسم ورقم الموبايل'));
    });

    test('does not call edit when only images were picked and all uploads fail', () async {
      var editCalled = false;
      try {
        await saveDelegateProfileEdit(
          upload: ({required delegateUid, required kind, required file}) async {
            throw DelegateProfileEditException('no web File');
          },
          edit: ({
            String? fullName,
            String? phoneNumber,
            String? personalPhotoURL,
            String? nationalIdFrontUrl,
            String? nationalIdBackUrl,
          }) async {
            editCalled = true;
          },
          delegateUid: 'd1',
          personalPhoto: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'p.jpg'),
        );
        fail('expected throw');
      } on DelegateProfileEditException catch (e) {
        expect(e.message, 'no web File');
        expect(editCalled, isFalse);
      }
    });

    test('uploads with the provided XFile and then edits URLs', () async {
      final kinds = <String>[];
      String? savedPhoto;
      final file = XFile.fromData(Uint8List.fromList([9, 8, 7]), name: 'p.jpg');
      final result = await saveDelegateProfileEdit(
        upload: ({required delegateUid, required kind, required file}) async {
          kinds.add(kind);
          expect(delegateUid, 'd1');
          expect(await file.readAsBytes(), [9, 8, 7]);
          return 'https://firebasestorage.googleapis.com/v0/b/tashil-dev.appspot.com/o/$kind';
        },
        edit: ({
          String? fullName,
          String? phoneNumber,
          String? personalPhotoURL,
          String? nationalIdFrontUrl,
          String? nationalIdBackUrl,
        }) async {
          savedPhoto = personalPhotoURL;
        },
        delegateUid: 'd1',
        personalPhoto: file,
      );
      expect(kinds, ['profile']);
      expect(savedPhoto, contains('profile'));
      expect(result.saved, isTrue);
      expect(result.imagesFailed, isFalse);
    });
  });
}
