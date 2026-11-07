import 'package:delegate_app/features/profile/presentation/utils/document_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final existing = [
    {
      'documentKey': 'personalPhoto',
      'documentStatus': 'approved',
      'documentURL': 'p0',
      'reviewedBy': 'sup',
    },
    {
      'documentKey': 'paymentReceipt',
      'documentStatus': 'approved',
      'documentURL': 'r0',
      'receiptCode': 'RC1',
    },
  ];

  test('delegate re-upload is pending and keeps other entries verbatim', () {
    final out = mergeReuploadedDocument(
      existing,
      docType: 'personalPhoto',
      newUrl: 'p1',
    );
    expect(out[0]['documentStatus'], 'pending');
    expect(out[0]['documentURL'], 'p1');
    expect(out[0].containsKey('reviewedBy'), isFalse);
    expect(out[1], existing[1]);
  });

  test('approver re-upload is approved with reviewer', () {
    final out = mergeReuploadedDocument(
      existing,
      docType: 'personalPhoto',
      newUrl: 'p1',
      approverUid: 'sa',
    );
    expect(out[0]['documentStatus'], 'approved');
    expect(out[0]['reviewedBy'], 'sa');
  });

  test('national ID back upload keeps front url, adds pending entry', () {
    final out = mergeReuploadedDocument(
      existing,
      docType: 'nationalIdBack',
      newUrl: 'b1',
    );
    final id = out.firstWhere((d) => d['documentKey'] == 'nationalityId');
    expect(id['secondaryURL'], 'b1');
    expect(id['documentURL'], '');
    expect(id['documentStatus'], 'pending');
    expect(out.length, 3);
  });

  test('review approve and reject', () {
    final pending = mergeReuploadedDocument(
      existing,
      docType: 'personalPhoto',
      newUrl: 'p1',
    );
    final ok = reviewDocumentEntry(
      pending,
      docType: 'personalPhoto',
      approve: true,
      reviewerUid: 'sup',
    )!;
    expect(ok[0]['documentStatus'], 'approved');
    final no = reviewDocumentEntry(
      pending,
      docType: 'personalPhoto',
      approve: false,
      reviewerUid: 'sup',
      rejectionReason: 'blurry',
    )!;
    expect(no[0]['documentStatus'], 'rejected');
    expect(no[0]['rejectionReason'], 'blurry');
    expect(
      reviewDocumentEntry(
        pending,
        docType: 'healthCertificate',
        approve: true,
        reviewerUid: 'x',
      ),
      isNull,
    );
  });
}
