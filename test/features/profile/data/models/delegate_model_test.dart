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

    test('should parse and serialize accountant role correctly', () {
      final jsonAccountant = {
        "uid": "acc_123",
        "firstName": "أحمد",
        "middleName": "",
        "lastName": "المحاسب",
        "fullName": "أحمد المحاسب",
        "phoneNumber": "01001989360",
        "role": "accountant",
        "birthDate": "2026-01-01T00:00:00.000",
        "createdAt": "2026-01-01T00:00:00.000",
      };

      final delegate = DelegateModel.fromJson(jsonAccountant, "acc_123");
      expect(delegate.role, UserRole.accountant);
      expect(DelegateModel.roleToString(delegate.role), 'accountant');

      final jsonAccounting = {
        ...jsonAccountant,
        "role": "accounting",
      };
      final delegate2 = DelegateModel.fromJson(jsonAccounting, "acc_123");
      expect(delegate2.role, UserRole.accountant);
    });

    test('should correctly parse and serialize hr role', () {
      final jsonHR = {
        "firstName": "سارة",
        "middleName": "",
        "lastName": "الموارد البشرية",
        "fullName": "سارة الموارد البشرية",
        "phoneNumber": "01001234567",
        "role": "hr",
        "birthDate": "2026-01-01T00:00:00.000",
        "createdAt": "2026-01-01T00:00:00.000",
      };

      final delegate = DelegateModel.fromJson(jsonHR, "hr_123");
      expect(delegate.role, UserRole.hr);
      expect(DelegateModel.roleToString(delegate.role), 'hr');

      final jsonCompanyHR = {
        ...jsonHR,
        "role": "company-hr",
      };
      final delegate2 = DelegateModel.fromJson(jsonCompanyHR, "hr_123");
      expect(delegate2.role, UserRole.hr);

      final jsonCompanyHRUnderscore = {
        ...jsonHR,
        "role": "company_hr",
      };
      final delegate3 = DelegateModel.fromJson(jsonCompanyHRUnderscore, "hr_123");
      expect(delegate3.role, UserRole.hr);
    });

    test('serializes superAdmin as super-admin and parses both legacy forms', () {
      expect(DelegateModel.roleToString(UserRole.superAdmin), 'super-admin');

      final base = {
        'firstName': 'Omar',
        'middleName': '',
        'lastName': 'Admin',
        'fullName': 'Omar Admin',
        'phoneNumber': '01000000000',
        'birthDate': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
      };

      for (final raw in ['super-admin', 'super_admin', 'superadmin', 'Super-Admin']) {
        final parsed = DelegateModel.fromJson({...base, 'role': raw}, 'sa');
        expect(parsed.role, UserRole.superAdmin, reason: raw);
      }

      final legacy = DelegateModel.fromJson({...base, 'role': 'super_admin'}, 'sa');
      expect(legacy.toLocalJson()['role'], 'super-admin');
      final roundTrip = DelegateModel.fromJson(legacy.toLocalJson(), 'sa');
      expect(roundTrip.role, UserRole.superAdmin);
      expect(DelegateModel.roleToString(roundTrip.role), 'super-admin');
    });
  });
}
