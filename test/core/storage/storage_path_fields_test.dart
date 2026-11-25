import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_audit_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_product_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-42: each changed field writes `<field>Path` (plus the old URL field
/// only when given) and reads the path first, the old URL otherwise.
void main() {
  const oldUrl = 'https://firebasestorage.googleapis.com/v0/b/b/o/x%2Fy.jpg?alt=media&token=t';

  group('captured_photos', () {
    CapturedPhotoModel model(String ref) => CapturedPhotoModel(
          uid: 'ph1',
          permissionId: 'p1',
          organizationUID: 'org_a',
          companyUID: 'co_1',
          branchId: 'b1',
          branchName: 'Fake branch',
          delegateUID: 'd1',
          delegateName: 'Fake',
          photoUrl: ref,
          comment: '',
          latitude: 30,
          longitude: 31,
          capturedAt: DateTime(2026, 11, 25),
        );
    const path = 'organizations/org_a/companies/co_1/permissions/p1/photo_d1_1.jpg';

    test('a new upload writes photoPath and, when given, the legacy photoUrl', () {
      final withUrl = capturedPhotoWriteData(model(path), legacyUrl: oldUrl);
      expect(withUrl['photoPath'], path);
      expect(withUrl['photoUrl'], oldUrl);

      final pathOnly = capturedPhotoWriteData(model(path));
      expect(pathOnly['photoPath'], path);
      expect(pathOnly.containsKey('photoUrl'), isFalse);
    });

    test('an old URL value is still written as photoUrl', () {
      final data = model(oldUrl).toFirestore();
      expect(data['photoUrl'], oldUrl);
      expect(data.containsKey('photoPath'), isFalse);
    });
  });

  group('penalties evidenceFiles', () {
    const path = 'penalties/co/evidence/p1/1_receipt.jpg';

    test('a new file stores filePath and the legacy fileUrl when present', () {
      const f = EvidenceFile(
        fileUrl: path,
        fileType: 'IMAGE',
        fileName: 'receipt.jpg',
        legacyUrl: oldUrl,
      );
      expect(f.toJson(), {
        'filePath': path,
        'fileUrl': oldUrl,
        'fileType': 'IMAGE',
        'fileName': 'receipt.jpg',
      });
      const noLegacy =
          EvidenceFile(fileUrl: path, fileType: 'PDF', fileName: 'a.pdf');
      expect(noLegacy.toJson().containsKey('fileUrl'), isFalse);
    });

    test('reads the path first and keeps the legacy URL on a rewrite', () {
      final f = EvidenceFile.fromJson({
        'filePath': path,
        'fileUrl': oldUrl,
        'fileType': 'IMAGE',
        'fileName': 'r.jpg',
      });
      expect(f.fileUrl, path);
      expect(f.toJson()['fileUrl'], oldUrl);
      expect(f.toJson()['filePath'], path);
    });

    test('an old document with only fileUrl reads and writes as before', () {
      final f = EvidenceFile.fromJson(
          {'fileUrl': oldUrl, 'fileType': 'IMAGE', 'fileName': 'r.jpg'});
      expect(f.fileUrl, oldUrl);
      expect(f.legacyUrl, isNull);
      expect(f.toJson(), {'fileUrl': oldUrl, 'fileType': 'IMAGE', 'fileName': 'r.jpg'});
    });
  });

  group('feedbacks', () {
    Map<String, dynamic> doc(Map<String, dynamic> extra) => {
          'userId': 'u',
          'userName': 'n',
          'userEmail': 'e',
          'type': 'other',
          'content': 'c',
          'status': 'pending',
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 25)),
          ...extra,
        };

    test('reads screenshotPath before screenshotUrl', () {
      expect(
        FeedbackModel.fromJson(
          doc({'screenshotPath': 'feedback_screenshots/a.jpg', 'screenshotUrl': oldUrl}),
          'f1',
        ).screenshotUrl,
        'feedback_screenshots/a.jpg',
      );
      expect(FeedbackModel.fromJson(doc({'screenshotUrl': oldUrl}), 'f1').screenshotUrl,
          oldUrl);
      expect(FeedbackModel.fromJson(doc({}), 'f1').screenshotUrl, isNull);
    });
  });

  group('private_label', () {
    final draft = PrivateLabelAuditDraft(
      id: 'a1',
      organizationUID: 'org_a',
      companyUID: 'co_1',
      delegateUid: 'd1',
      delegateName: 'Fake',
      branchName: 'Fake branch',
      productName: 'Rice',
      shelfPrice: 10,
      stockStatus: PrivateLabelStockStatus.available,
      productImagePath: '/tmp/p.jpg',
      priceImagePath: '/tmp/q.jpg',
      capturedAt: DateTime(2026, 11, 25, 9),
    );

    test('audit stores both paths and the URLs only when given', () {
      final withUrls = PrivateLabelAuditModel.firestoreFromDraft(
        draft,
        productPhotoPath: 'organizations/org_a/private_label/2026-11/a1_product.jpg',
        pricePhotoPath: 'organizations/org_a/private_label/2026-11/a1_price.jpg',
        productPhotoUrl: oldUrl,
        pricePhotoUrl: oldUrl,
      );
      expect(withUrls['productPhotoPath'], endsWith('a1_product.jpg'));
      expect(withUrls['pricePhotoPath'], endsWith('a1_price.jpg'));
      expect(withUrls['productPhotoUrl'], oldUrl);

      final pathsOnly = PrivateLabelAuditModel.firestoreFromDraft(
        draft,
        productPhotoPath: 'x/a1_product.jpg',
        pricePhotoPath: 'x/a1_price.jpg',
      );
      expect(pathsOnly.containsKey('productPhotoUrl'), isFalse);
      expect(pathsOnly.containsKey('pricePhotoUrl'), isFalse);
    });

    test('audit reads paths first, URLs for old docs', () {
      final fresh = PrivateLabelAuditModel.fromJson({
        'productPhotoPath': 'x/a1_product.jpg',
        'pricePhotoPath': 'x/a1_price.jpg',
        'productPhotoUrl': oldUrl,
        'pricePhotoUrl': oldUrl,
      }, 'a1');
      expect(fresh.productPhotoUrl, 'x/a1_product.jpg');
      expect(fresh.pricePhotoUrl, 'x/a1_price.jpg');

      final old = PrivateLabelAuditModel.fromJson(
          {'productPhotoUrl': oldUrl, 'pricePhotoUrl': oldUrl}, 'a1');
      expect(old.productPhotoUrl, oldUrl);
      expect(old.pricePhotoUrl, oldUrl);
    });

    test('product writes imagePath for a Storage path, imageUrl otherwise', () {
      const stored = PrivateLabelProductModel(
        id: 'p1',
        organizationUID: 'org_a',
        name: 'Rice',
        imageUrl: 'organizations/org_a/private_label_products/p1.jpg',
      );
      expect(stored.toJson()['imagePath'], stored.imageUrl);
      expect(stored.toJson().containsKey('imageUrl'), isFalse);

      const asset = PrivateLabelProductModel(
        id: 'p1',
        organizationUID: 'org_a',
        name: 'Rice',
        imageUrl: 'assets/images/private_label/wixmax.jpg',
      );
      expect(asset.toJson()['imageUrl'], asset.imageUrl);
      expect(asset.toJson().containsKey('imagePath'), isFalse);
    });

    test('product reads imagePath before imageUrl', () {
      final p = PrivateLabelProductModel.fromJson({
        'name': 'X',
        'imagePath': 'organizations/o/private_label_products/p1.jpg',
        'imageUrl': oldUrl,
      }, 'p1');
      expect(p.imageUrl, 'organizations/o/private_label_products/p1.jpg');
      final old = PrivateLabelProductModel.fromJson({'name': 'X', 'imageUrl': oldUrl}, 'p1');
      expect(old.imageUrl, oldUrl);
    });
  });
}
