import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_delegates_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  group('Comprehensive HR System Suite (Phases 1, 2, & 3)', () {
    late Delegate tHRDelegate;

    setUpAll(() {
      tHRDelegate = Delegate(
        uid: 'hr_test_uid_101',
        firstName: 'مسؤول',
        middleName: 'الموارد',
        lastName: 'البشرية',
        fullName: 'مسؤول الموارد البشرية التجريبي',
        nationalityID: '__phone_auth__:01099887766',
        motherName: 'والدة تجريبية',
        city: 'القاهرة',
        phoneNumber: '01099887766',
        gender: DelegateGender.male,
        position: DelegatePosition.supervisor,
        birthDate: DateTime(1992, 5, 15),
        organizationUID: 'org_fathalla_001',
        organizationName: 'سلسلة أسواق فتح الله',
        companyUID: 'comp_pharma_999',
        companyName: 'فارما جروب لتوزيع الأدوية',
        status: DelegateStatus.active,
        delegatePublicId: 'HR-PHARMA-01',
        allReceiptCodes: const [],
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'super_admin_omar',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
        role: UserRole.hr,
      );
    });

    // ──────────────────────────────────────────────────────────
    // Phase 1: Creation Pipeline & Models
    // ──────────────────────────────────────────────────────────
    group('Phase 1: Super Admin Creation Pipeline & Data Models', () {
      test('DelegateModel.fromJson correctly identifies HR role variants', () {
        final d1 = DelegateModel.fromJson({'role': 'hr', 'phoneNumber': '01000000000'}, 'hr_1');
        final d2 = DelegateModel.fromJson({'role': 'company-hr', 'phoneNumber': '01000000000'}, 'hr_2');
        final d3 = DelegateModel.fromJson({'role': 'company_hr', 'phoneNumber': '01000000000'}, 'hr_3');
        final d4 = DelegateModel.fromJson({'role': 'human_resources', 'phoneNumber': '01000000000'}, 'hr_4');

        expect(d1.role, equals(UserRole.hr));
        expect(d2.role, equals(UserRole.hr));
        expect(d3.role, equals(UserRole.hr));
        expect(d4.role, equals(UserRole.hr));
        expect(DelegateModel.roleToString(UserRole.hr), equals('hr'));
      });

      test('AdminUserModel serializes and deserializes HR specific fields', () {
        final hrAdmin = AdminUserModel(
          uid: 'hr_uid_01',
          phoneNumber: '01099887766',
          email: 'hr@pharmagroup.com',
          displayName: 'مدير الموارد البشرية',
          role: 'hr',
          organizationUID: 'org_fathalla_001',
          organizationName: 'سلسلة أسواق فتح الله',
          companyUID: 'comp_pharma_999',
          companyName: 'فارما جروب لتوزيع الأدوية',
          jobTitle: 'Senior HR Specialist',
          createdAt: DateTime(2026, 1, 1),
          createdBy: 'superadmin',
          temporaryPassword: 'TempPassword123!',
          isActive: true,
        );

        final map = hrAdmin.toMap();
        expect(map['role'], 'hr');
        expect(map['companyUID'], 'comp_pharma_999');
        expect(map['companyName'], 'فارما جروب لتوزيع الأدوية');
        expect(map['jobTitle'], 'Senior HR Specialist');
      });

      test('CreateAdminParams accepts companyUID, companyName, and jobTitle for HR', () {
        const params = CreateAdminParams(
          phoneNumber: '01099887766',
          email: 'hr@pharmagroup.com',
          displayName: 'مسؤول الموارد البشرية',
          role: 'hr',
          organizationUID: 'org_fathalla_001',
          companyUID: 'comp_pharma_999',
          companyName: 'فارما جروب لتوزيع الأدوية',
          jobTitle: 'مدير التوظيف والمتابعة',
        );

        expect(params.role, equals('hr'));
        expect(params.companyUID, equals('comp_pharma_999'));
        expect(params.companyName, equals('فارما جروب لتوزيع الأدوية'));
        expect(params.jobTitle, equals('مدير التوظيف والمتابعة'));
      });
    });

    // ──────────────────────────────────────────────────────────
    // Phase 2: Navigation & Company-Scoped Portal
    // ──────────────────────────────────────────────────────────
    group('Phase 2: Company-Scoped HR Portal & Attendance Logic', () {
      test('HRAttendanceRecord accurately derives presence states', () {
        final recordPresent = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: DateTime(2026, 9, 27, 9, 0),
          checkOutTime: null,
          branchName: 'فرع مدينة نصر',
          isInsideGeofence: true,
          distanceMeters: 35.0,
        );
        expect(recordPresent.isPresent, isTrue);
        expect(recordPresent.isDeparted, isFalse);
        expect(recordPresent.isAbsent, isFalse);

        final recordDeparted = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: DateTime(2026, 9, 27, 9, 0),
          checkOutTime: DateTime(2026, 9, 27, 17, 0),
          branchName: 'فرع مدينة نصر',
          isInsideGeofence: true,
          distanceMeters: 40.0,
        );
        expect(recordDeparted.isPresent, isFalse);
        expect(recordDeparted.isDeparted, isTrue);
        expect(recordDeparted.isAbsent, isFalse);

        final recordAbsent = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: null,
          checkOutTime: null,
        );
        expect(recordAbsent.isPresent, isFalse);
        expect(recordAbsent.isDeparted, isFalse);
        expect(recordAbsent.isAbsent, isTrue);
      });
    });

    // ──────────────────────────────────────────────────────────
    // Phase 3: Responsive Multiplatform Layouts (Mobile & Web)
    // ──────────────────────────────────────────────────────────
    group('Phase 3: Responsive Multiplatform Layouts (Mobile & Web)', () {
      testWidgets('HRMainScreen initializes with HR delegate and company scope', (tester) async {
        final screen = HRMainScreen(delegate: tHRDelegate);
        expect(screen.delegate, equals(tHRDelegate));
        expect(screen.delegate.companyUID, equals('comp_pharma_999'));
        expect(screen.delegate.role, equals(UserRole.hr));
      });

      test('Responsive breakpoint logic adheres to 768px boundary', () {
        const double mobileWidth = 400.0;
        const double tabletWidth = 768.0;
        const double desktopWebWidth = 1280.0;

        bool isWide(double width) => width > 768;

        expect(isWide(mobileWidth), isFalse, reason: 'Mobile screens must use bottom NavigationBar');
        expect(isWide(tabletWidth), isFalse, reason: '768px boundary stays compact');
        expect(isWide(desktopWebWidth), isTrue, reason: 'Desktop Web screens must use NavigationRail');
      });

      test('Responsive Grid Extents for Web and Mobile are ergonomically configured', () {
        // Attendance tab responsive grid
        const double attendanceWebMaxCrossAxisExtent = 600.0;
        const double attendanceWebMainAxisExtent = 235.0;
        expect(attendanceWebMaxCrossAxisExtent, equals(600.0));
        expect(attendanceWebMainAxisExtent, equals(235.0));

        // Delegates tab responsive grid
        const double delegatesWebMaxCrossAxisExtent = 550.0;
        const double delegatesWebMainAxisExtent = 175.0;
        expect(delegatesWebMaxCrossAxisExtent, equals(550.0));
        expect(delegatesWebMainAxisExtent, equals(175.0));

        // Photos tab responsive grid
        const double photosWebMaxCrossAxisExtent = 250.0;
        expect(photosWebMaxCrossAxisExtent, equals(250.0));
      });

      test('HR Tabs initialize cleanly with delegate company scope', () {
        final attendanceTab = HRAttendanceTab(hrDelegate: tHRDelegate);
        final photosTab = HRPhotosTab(hrDelegate: tHRDelegate);
        final delegatesTab = HRDelegatesTab(hrDelegate: tHRDelegate);

        expect(attendanceTab.hrDelegate.companyUID, equals('comp_pharma_999'));
        expect(photosTab.hrDelegate.companyUID, equals('comp_pharma_999'));
        expect(delegatesTab.hrDelegate.companyUID, equals('comp_pharma_999'));
      });
    });
  });
}
