// TAS-363: HR sees «بدون إنترنت» on offline records (a flag, not a pay rule).
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online record: no flag', () {
    expect(offlineAttendanceFlag({'type': 'check_in'}, null).any, isFalse);
  });

  test('offline check-in with trusted time', () {
    final f = offlineAttendanceFlag({
      'offlineCheckIn': true,
      'timeTrusted': true,
    }, null);
    expect(f.checkIn, isTrue);
    expect(f.checkOut, isFalse);
    expect(f.timeUntrusted, isFalse);
  });

  test('offline check-out with untrusted time (from either record)', () {
    final a = offlineAttendanceFlag({
      'offlineCheckOut': true,
      'checkOutTimeTrusted': false,
    }, null);
    expect(a.checkOut, isTrue);
    expect(a.timeUntrusted, isTrue);
    final b = offlineAttendanceFlag({}, {
      'offlineCheckOut': true,
      'timeTrusted': false,
    });
    expect(b.checkOut, isTrue);
    expect(b.timeUntrusted, isTrue);
  });
}
