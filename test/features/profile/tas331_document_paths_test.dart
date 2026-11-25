import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/utils/document_review.dart';
import 'package:flutter_test/flutter_test.dart';

String _url(String path) =>
    'https://firebasestorage.googleapis.com/v0/b/tashil-dev.firebasestorage.app/o/'
    '${Uri.encodeComponent(path)}?alt=media&token=fake-token';

/// TAS-331: delegate documents store a Storage path next to the legacy URL.
void main() {
  const p1 = 'delegate_documents/d1/personalPhoto_1.jpg';
  const p2 = 'delegate_documents/d1/personalPhoto_2.jpg';

  tearDown(StorageMediaRef.clearLegacyUrls);

  group('StorageMediaRef.pickFresh', () {
    test('path wins when the URL names the same object', () {
      expect(StorageMediaRef.pickFresh(path: p1, url: _url(p1)), p1);
    });
    test('a newer URL (other object) wins over a stale path', () {
      expect(StorageMediaRef.pickFresh(path: p1, url: _url(p2)), _url(p2));
    });
    test('one side empty: the other', () {
      expect(StorageMediaRef.pickFresh(path: p1, url: ''), p1);
      expect(StorageMediaRef.pickFresh(path: '', url: _url(p1)), _url(p1));
      expect(StorageMediaRef.pickFresh(path: null, url: null), '');
    });
  });

  group('DelegateDocument display values', () {
    test('displayUrl / secondaryDisplayUrl read path-first', () {
      final d = DelegateDocument(
        documentKey: DocumentKey.nationalityId,
        documentStatus: DocumentStatus.pending,
        documentURL: _url('delegate_documents/d1/f.jpg'),
        documentPath: 'delegate_documents/d1/f.jpg',
        secondaryURL: '',
        secondaryPath: 'delegate_documents/d1/b.jpg',
      );
      expect(d.displayUrl, 'delegate_documents/d1/f.jpg');
      expect(d.secondaryDisplayUrl, 'delegate_documents/d1/b.jpg');
    });
  });

  group('mergeReuploadedDocument', () {
    test('writes documentPath next to the URL, pending for the delegate', () {
      final out = mergeReuploadedDocument(
        [
          {
            'documentKey': 'personalPhoto',
            'documentStatus': 'approved',
            'documentURL': 'old',
          },
        ],
        docType: 'personalPhoto',
        newUrl: _url(p1),
        newPath: p1,
      );
      expect(out.single['documentPath'], p1);
      expect(out.single['documentURL'], _url(p1));
      expect(out.single['documentStatus'], 'pending');
    });
    test(
      'ID back goes to secondaryPath; a URL-only write drops the stale path',
      () {
        final withPath = mergeReuploadedDocument(
          [
            {
              'documentKey': 'nationalityId',
              'documentStatus': 'approved',
              'documentURL': 'f',
              'documentPath': 'delegate_documents/d1/f.jpg',
            },
          ],
          docType: 'nationalIdBack',
          newUrl: '',
          newPath: 'delegate_documents/d1/b.jpg',
        );
        expect(withPath.single['secondaryPath'], 'delegate_documents/d1/b.jpg');
        expect(withPath.single['documentPath'], 'delegate_documents/d1/f.jpg');

        final urlOnly = mergeReuploadedDocument(
          withPath,
          docType: 'nationalIdBack',
          newUrl: 'u2',
        );
        expect(urlOnly.single.containsKey('secondaryPath'), isFalse);
        expect(urlOnly.single['secondaryURL'], 'u2');
      },
    );
  });

  group('requests carry the paths', () {
    final req = DelegateSubscriptionRequest.fromMap({
      'supervisorUid': 's',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'fullName': 'Fake',
      'phoneNumber': '010',
      'nationalId': '1',
      'profileImageUrl': _url(p1),
      'profileImagePath': p1,
      'nationalIdFrontUrl': '',
      'nationalIdFrontPath': 'delegate_documents/d1/f.jpg',
      'nationalIdBackUrl': '',
      'nationalIdBackPath': 'delegate_documents/d1/b.jpg',
      'receiptImageUrl': '',
      'receiptImagePath': 'delegate_subscription_receipts/d1/receipt.jpg',
      'receiptCode': 'RC1',
      'status': 'pending',
    }, 'd1');

    test('fromMap reads the path fields', () {
      expect(req.profileImagePath, p1);
      expect(req.nationalIdBackPath, 'delegate_documents/d1/b.jpg');
      expect(
        req.receiptImagePath,
        'delegate_subscription_receipts/d1/receipt.jpg',
      );
    });

    test('approval writes each path next to its URL', () {
      expect(requestPathFields(req), {
        'profileImagePath': p1,
        'nationalIdFrontPath': 'delegate_documents/d1/f.jpg',
        'nationalIdBackPath': 'delegate_documents/d1/b.jpg',
        'receiptImagePath': 'delegate_subscription_receipts/d1/receipt.jpg',
      });
      final docs = approvedDocumentsFromRequest(req, DateTime(2026, 11, 25));
      expect(docs.map((d) => d['documentKey']), [
        'personalPhoto',
        'nationalityId',
        'paymentReceipt',
      ]);
      expect(docs[0]['documentPath'], p1);
      expect(docs[1]['documentPath'], 'delegate_documents/d1/f.jpg');
      expect(docs[1]['secondaryPath'], 'delegate_documents/d1/b.jpg');
      expect(
        docs[2]['documentPath'],
        'delegate_subscription_receipts/d1/receipt.jpg',
      );
      expect(docs.every((d) => d['documentStatus'] == 'approved'), isTrue);
    });

    test('a request written before TAS-331 adds no path keys', () {
      final old = DelegateSubscriptionRequest.fromMap({
        'supervisorUid': 's',
        'companyUID': 'c1',
        'organizationUID': 'o1',
        'fullName': 'Fake',
        'profileImageUrl': 'p0',
        'status': 'pending',
      }, 'd2');
      expect(requestPathFields(old), isEmpty);
      final docs = approvedDocumentsFromRequest(old, DateTime(2026, 11, 25));
      expect(docs.single.containsKey('documentPath'), isFalse);
    });
  });

  test('existingDelegateDocumentRefs drops a path a newer URL replaced', () {
    final d = DelegateModel.fromJson({
      'documents': [
        {
          'documentKey': 'personalPhoto',
          'documentStatus': 'approved',
          'documentURL': _url(p2),
          'documentPath': p1,
        },
        {
          'documentKey': 'nationalityId',
          'documentStatus': 'approved',
          'documentURL': _url('delegate_documents/d1/f.jpg'),
          'documentPath': 'delegate_documents/d1/f.jpg',
          'secondaryURL': '',
          'secondaryPath': 'delegate_documents/d1/b.jpg',
        },
      ],
    }, 'd1');
    final refs = existingDelegateDocumentRefs(d);
    expect(refs.profileUrl, _url(p2));
    expect(refs.profilePath, '');
    expect(refs.frontPath, 'delegate_documents/d1/f.jpg');
    expect(refs.backPath, 'delegate_documents/d1/b.jpg');
  });
}
