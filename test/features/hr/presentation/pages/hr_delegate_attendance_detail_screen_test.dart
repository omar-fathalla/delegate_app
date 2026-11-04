import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tDelegate;

  setUpAll(() {
    tDelegate = Delegate(
      uid: 'del_123',
      firstName: 'Fatma',
      middleName: 'M',
      lastName: 'Ahmed',
      fullName: 'فاطمة محمد أحمد',
      nationalityID: '29801010101234',
      motherName: 'Mother',
      city: 'Alexandria',
      phoneNumber: '01285566032',
      gender: DelegateGender.female,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1998, 5, 12),
      organizationUID: 'org1',
      organizationName: 'Gomla Market',
      companyUID: 'comp1',
      companyName: 'Johnson & Johnson',
      status: DelegateStatus.active,
      delegatePublicId: 'del_pub123',
      allReceiptCodes: const [],
      createdAt: DateTime(2024, 1, 1),
      createdBy: 'super_admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.delegate,
      boundDeviceModel: 'iPhone iOS 26.7',
    );
  });

  group('HRDelegateAttendanceDetailScreen & DelegateAttendanceSession Tests', () {
    test('DelegateAttendanceSession calculates duration and formattedDuration correctly', () {
      final checkIn = DateTime(2026, 9, 27, 9, 15);
      final checkOut = DateTime(2026, 9, 27, 17, 45); // 8h 30m

      final session = DelegateAttendanceSession(
        id: 'sess_1',
        checkInTime: checkIn,
        checkOutTime: checkOut,
        branchName: 'Agmy Star',
        deviceInfo: 'iPhone iOS 26.7',
      );

      expect(session.duration, equals(const Duration(hours: 8, minutes: 30)));
      expect(session.formattedDuration, equals('8 س و 30 د'));
      expect(session.isOngoing, isFalse);
    });

    test('DelegateAttendanceSession handles null checkOutTime and ongoing status', () {
      final now = DateTime.now();
      // Stay on today's date even when the test runs shortly after midnight
      // (CI runs in UTC), otherwise isOngoing is legitimately false.
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      final checkInToday = twoHoursAgo.day == now.day
          ? twoHoursAgo
          : DateTime(now.year, now.month, now.day);

      final sessionToday = DelegateAttendanceSession(
        id: 'sess_today',
        checkInTime: checkInToday,
        checkOutTime: null,
        branchName: 'Smoha',
      );

      expect(sessionToday.duration, isNull);
      expect(sessionToday.isOngoing, isTrue);
      expect(sessionToday.formattedDuration, equals('قيد العمل الآن'));

      final pastDate = DateTime(2026, 1, 1, 10, 0);
      final sessionPast = DelegateAttendanceSession(
        id: 'sess_past',
        checkInTime: pastDate,
        checkOutTime: null,
        branchName: 'Smoha',
      );

      expect(sessionPast.isOngoing, isFalse);
      expect(sessionPast.formattedDuration, equals('غير مسجل'));
    });

    test('HRDelegateAttendanceDetailScreen constructor holds valid delegate and month references', () {
      final initialMonth = DateTime(2026, 8, 1);
      final screen = HRDelegateAttendanceDetailScreen(
        delegate: tDelegate,
        initialMonth: initialMonth,
      );

      expect(screen.delegate, equals(tDelegate));
      expect(screen.initialMonth, equals(initialMonth));
      expect(screen.delegate.fullName, equals('فاطمة محمد أحمد'));
      expect(screen.delegate.phoneNumber, equals('01285566032'));
      expect(screen.delegate.boundDeviceModel, equals('iPhone iOS 26.7'));
    });
  });
}
