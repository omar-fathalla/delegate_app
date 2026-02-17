import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DelegateModel', () {
    test('should parse JSON correctly with all new fields', () {
      final json = {
        "allReceiptCodes": ["0", "13811211120126", "0049992"],
        "birthDate": Timestamp.fromDate(DateTime(1993, 7, 30)),
        "city": "الغربية",
        "companyName": "جراند",
        "companyUID": "02kPiIXkBOC9nHX054vB",
        "createdAt": Timestamp.fromDate(DateTime(2026, 1, 12, 18, 23, 25)),
        "createdBy": "xzZmvDZPpdNP3tU9KJWTWqbbEdR2",
        "delegatePublicId": "DEL-0487",
        "documents": [
          {
            "documentKey": "personalPhoto",
            "documentStatus": "approved",
            "documentURL": "https://example.com/photo.jpg",
            "reviewedAt": Timestamp.fromDate(DateTime(2026, 1, 12, 21, 15, 57)),
            "reviewedBy": "1q6sjv5xOohfoaeVMZWzrhhfAAM2",
            "uploadedAt": Timestamp.fromDate(DateTime(2026, 1, 12, 18, 23, 25)),
          },
          {
            "documentKey": "healthCertificate",
            "documentStatus": "not_provided",
          },
        ],
        "firstName": "نادية",
        "fullName": "نادية مصطفى مصطفى",
        "gender": "Female",
        "hasPendingUpdate": false,
        "isDeductedFromCompany": false,
        "isPrinted": true,
        "isProfileComplete": false,
        "lastName": "مصطفى",
        "latestRequestId": null,
        "middleName": "مصطفى",
        "motherName": "سهير رجب",
        "nationalityID": "29307030160246",
        "numberOfDocuments": 5,
        "organizationName": "fathalla market",
        "organizationUID": "PiioBFgxaHAeuRdjlDgj",
        "paymentAmount": 100,
        "phoneNumber": "01141762624",
        "position": "Promoter",
        "receiptCode": "13811211120126",
        "status": "active",
        "statusReason": "create",
        "uid": "4TbDLWI5xnCcyRUrH3TT",
        "updatedAt": Timestamp.fromDate(DateTime(2026, 1, 13, 17, 48, 35)),
        "updatedBy": "1q6sjv5xOohfoaeVMZWzrhhfAAM2",
        "version": 1,
      };

      final delegate = DelegateModel.fromJson(json, "4TbDLWI5xnCcyRUrH3TT");

      expect(delegate.allReceiptCodes, ["0", "13811211120126", "0049992"]);
      expect(delegate.birthDate, DateTime(1993, 7, 30));
      expect(delegate.city, "الغربية");
      expect(delegate.companyName, "جراند");
      expect(delegate.createdAt, DateTime(2026, 1, 12, 18, 23, 25));
      expect(delegate.delegatePublicId, "DEL-0487");
      expect(delegate.documents.length, 2);
      expect(delegate.documents[0].documentKey, DocumentKey.personalPhoto);
      expect(delegate.documents[0].documentStatus, DocumentStatus.approved);
      expect(delegate.documents[1].documentKey, DocumentKey.healthCertificate);
      expect(delegate.documents[1].documentStatus, DocumentStatus.notProvided);
      expect(delegate.firstName, "نادية");
      expect(delegate.fullName, "نادية مصطفى مصطفى");
      expect(delegate.gender, DelegateGender.female);
      expect(delegate.hasPendingUpdate, false);
      expect(delegate.isDeductedFromCompany, false);
      expect(delegate.isPrinted, true);
      expect(delegate.isProfileComplete, false);
      expect(delegate.lastName, "مصطفى");
      expect(delegate.motherName, "سهير رجب");
      expect(delegate.nationalityID, "29307030160246");
      expect(delegate.numberOfDocuments, 5);
      expect(delegate.organizationName, "fathalla market");
      expect(delegate.paymentAmount, 100);
      expect(delegate.position, DelegatePosition.promoter);
      expect(delegate.status, DelegateStatus.active);
      expect(delegate.statusReason, "create");
      expect(delegate.updatedAt, DateTime(2026, 1, 13, 17, 48, 35));
      expect(delegate.version, 1);
    });
  });
}
