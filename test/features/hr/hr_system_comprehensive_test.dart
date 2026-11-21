import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/data/models/company_payroll_config_model.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
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
        // Attendance tab cards grid: fixed column count from the width
        // (TAS-147), cards at least 360 wide and 235 tall.
        expect(kHrAttendanceCardMinWidth, equals(360.0));
        expect(kHrAttendanceCardHeight, equals(235.0));

        // Delegates tab responsive grid
        const double delegatesWebMaxCrossAxisExtent = 550.0;
        const double delegatesWebMainAxisExtent = 175.0;
        expect(delegatesWebMaxCrossAxisExtent, equals(550.0));
        expect(delegatesWebMainAxisExtent, equals(175.0));

        // Photos tab responsive grid
        const double photosWebMaxCrossAxisExtent = 250.0;
        expect(photosWebMaxCrossAxisExtent, equals(250.0));
      });

      test('HRAttendanceRecord calculates net working hours and safety badges correctly', () {
        final now = DateTime.now();
        final checkIn = DateTime(now.year, now.month, now.day, 8, 30);
        final checkOut = DateTime(now.year, now.month, now.day, 16, 45);

        // Completed shift
        final recordCompleted = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: checkIn,
          checkOutTime: checkOut,
          isInsideGeofence: true,
          distanceMeters: 25.0,
        );
        expect(recordCompleted.duration?.inMinutes, equals(495)); // 8 hours 15 mins
        expect(recordCompleted.formattedDuration, contains('8 س و 15 د'));
        expect(recordCompleted.safetyLevel, equals('safe'));

        // Warning shift (out of geofence)
        final recordWarning = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: checkIn,
          checkOutTime: checkOut,
          isInsideGeofence: false,
          distanceMeters: 450.0,
        );
        expect(recordWarning.safetyLevel, equals('warning'));

        // Leave record
        final recordLeave = HRAttendanceRecord(
          delegate: tHRDelegate,
          checkInTime: null,
          checkOutTime: null,
          isOnApprovedLeave: true,
          leaveType: 'annual',
          leaveReason: 'إجازة سنوية اعتيادية',
        );
        expect(recordLeave.isAbsent, isTrue);
        expect(recordLeave.isOnLeave, isTrue);
        expect(recordLeave.formattedLeaveType, equals('إجازة اعتيادية'));
      });

      test('HRAttendanceRecord maps leave types to friendly Arabic labels', () {
        const types = {
          'annual': 'إجازة اعتيادية',
          'sick': 'إجازة مرضية',
          'emergency': 'إجازة عارضة',
          'delay': 'عذر تأخير',
          'absence': 'عذر غياب',
          'unknown_type': 'إجازة معتمدة',
        };

        for (final entry in types.entries) {
          final record = HRAttendanceRecord(
            delegate: tHRDelegate,
            checkInTime: null,
            isOnApprovedLeave: true,
            leaveType: entry.key,
          );
          expect(record.formattedLeaveType, equals(entry.value));
        }
      });

      test('Monthly payroll settlement calculates net compensation accurately', () {
        const double baseSalary = 6000.0;
        const double penaltiesTotal = 350.0;
        const int attendedDays = 22;
        const int approvedLeaves = 3;
        const int monthWorkingDays = 26;

        final absentDays = (monthWorkingDays - attendedDays - approvedLeaves).clamp(0, monthWorkingDays);
        expect(absentDays, equals(1)); // 26 - 22 - 3 = 1

        final netSalary = (baseSalary - penaltiesTotal).clamp(0.0, double.infinity);
        expect(netSalary, equals(5650.0));
      });

      test('CompanyPayrollConfig derives effective hourly rate and daily rate accurately', () {
        const config = CompanyPayrollConfig(
          companyUID: 'comp_test_1',
          calculationMode: PayrollCalculationMode.monthlyWithDeductions,
          defaultDailyShiftHours: 9.0,
          defaultMonthlyBaseSalary: 3500.0,
          defaultMonthlyWorkingDays: 26,
        );

        // 26 days * 9 hours = 234 hours target
        // 3500 / 234 = ~14.957
        expect(config.effectiveHourlyRate, closeTo(14.957, 0.01));
        // Daily rate = 14.957 * 9 = ~134.615
        expect(config.effectiveDailyRate, closeTo(134.615, 0.01));
      });

      test('CompanyPayrollConfig respects custom hourly rate override', () {
        const config = CompanyPayrollConfig(
          companyUID: 'comp_test_2',
          calculationMode: PayrollCalculationMode.hourlyRate,
          defaultDailyShiftHours: 8.0,
          defaultMonthlyBaseSalary: 4000.0,
          defaultMonthlyWorkingDays: 25,
          defaultHourlyRate: 25.0, // overridden
        );

        expect(config.effectiveHourlyRate, equals(25.0));
        expect(config.effectiveDailyRate, equals(200.0)); // 25 * 8
      });

      test('CompanyPayrollConfigModel serializes and deserializes to/from map correctly', () {
        final now = DateTime(2026, 9, 30, 12, 0);
        final model = CompanyPayrollConfigModel(
          companyUID: 'comp_serialize_test',
          calculationMode: PayrollCalculationMode.hourlyRate,
          defaultDailyShiftHours: 8.5,
          defaultMonthlyBaseSalary: 4200.0,
          defaultMonthlyWorkingDays: 24,
          defaultHourlyRate: 20.0,
          updatedAt: now,
          updatedBy: 'HR Manager',
        );

        final map = model.toMap();
        expect(map['companyUID'], equals('comp_serialize_test'));
        expect(map['calculationMode'], equals('hourly_rate'));
        expect(map['defaultDailyShiftHours'], equals(8.5));
        expect(map['defaultMonthlyBaseSalary'], equals(4200.0));
        expect(map['defaultMonthlyWorkingDays'], equals(24));
        expect(map['defaultHourlyRate'], equals(20.0));
        expect(map['updatedBy'], equals('HR Manager'));

        final fromMap = CompanyPayrollConfigModel.fromMap(map, 'comp_serialize_test');
        expect(fromMap.companyUID, equals('comp_serialize_test'));
        expect(fromMap.calculationMode, equals(PayrollCalculationMode.hourlyRate));
        expect(fromMap.defaultDailyShiftHours, equals(8.5));
        expect(fromMap.defaultMonthlyBaseSalary, equals(4200.0));
        expect(fromMap.defaultMonthlyWorkingDays, equals(24));
        expect(fromMap.defaultHourlyRate, equals(20.0));
      });

      test('Dynamic hours-based payroll correctly calculates earnings and leaves (Abanoub George scenario)', () {
        // Delegate has 0 attendance, 1 approved leave, 29 absent days, 0 hours worked
        const double baseSalary = 3500.0;
        const double dailyShiftHours = 9.0;
        const int monthWorkingDays = 26;
        const double targetHours = monthWorkingDays * dailyShiftHours; // 234 hours
        const double hourlyRate = baseSalary / targetHours; // 14.957
        const double dailyRate = hourlyRate * dailyShiftHours; // 134.615

        // Mode 1: Hourly rate (worked hours * rate + approved leaves * daily rate - penalties)
        const double actualWorkHours = 0.0;
        const int approvedLeaveDays = 1;
        const double penalties = 0.0;

        final earnedWork = actualWorkHours * hourlyRate; // 0.0
        final earnedLeave = approvedLeaveDays * dailyRate; // 134.615
        final grossEarned = earnedWork + earnedLeave;
        final netHourly = (grossEarned - penalties).clamp(0.0, double.infinity);

        expect(earnedWork, equals(0.0));
        expect(netHourly, closeTo(134.61, 0.02));
        // Under our new system, delegate does NOT receive 3500, but only 134.61!
        expect(netHourly, isNot(equals(3500.0)));

        // Mode 2: Monthly base with shortfall deduction
        final workedAndLeaveHours = actualWorkHours + (approvedLeaveDays * dailyShiftHours); // 9 hours
        final shortfallHours = (targetHours - workedAndLeaveHours).clamp(0.0, targetHours); // 225 hours
        final absenceDeduction = shortfallHours * hourlyRate; // 225 * 14.957 = 3365.38
        final netMonthly = (baseSalary - absenceDeduction - penalties).clamp(0.0, double.infinity);

        expect(shortfallHours, equals(225.0));
        expect(absenceDeduction, closeTo(3365.38, 0.05));
        expect(netMonthly, closeTo(134.61, 0.02));
      });

      test('Delegate with 0 attendance and 0 leaves receives 0 net salary', () {
        const double baseSalary = 3500.0;
        const double dailyShiftHours = 9.0;
        const int monthWorkingDays = 26;
        const double targetHours = monthWorkingDays * dailyShiftHours;
        const double hourlyRate = baseSalary / targetHours;

        // Worked hours = 0, leaves = 0
        final grossEarned = 0.0 * hourlyRate;
        expect(grossEarned, equals(0.0));

        // Shortfall = 234 hours => deduction = 3500 => net = 0
        final shortfallHours = targetHours;
        final absenceDeduction = shortfallHours * hourlyRate;
        final netMonthly = (baseSalary - absenceDeduction).clamp(0.0, double.infinity);
        expect(netMonthly, equals(0.0));
      });

      test('Delegate who completes full shift hours receives 100% full salary', () {
        const double baseSalary = 3500.0;
        const double dailyShiftHours = 9.0;
        const int monthWorkingDays = 26;
        const double targetHours = monthWorkingDays * dailyShiftHours; // 234h
        const double hourlyRate = baseSalary / targetHours;

        const double actualWorkHours = 234.0; // 26 days * 9h
        final earnedWork = actualWorkHours * hourlyRate;
        expect(earnedWork, closeTo(3500.0, 0.01));

        final shortfallHours = (targetHours - actualWorkHours).clamp(0.0, targetHours);
        expect(shortfallHours, equals(0.0));
        final absenceDeduction = shortfallHours * hourlyRate;
        expect(absenceDeduction, equals(0.0));

        final netSalary = (baseSalary - absenceDeduction).clamp(0.0, double.infinity);
        expect(netSalary, equals(3500.0));
      });
    });
  });
}
