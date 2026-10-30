import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String label(UserRole r, {DelegatePosition? p, String? raw}) =>
      UniversalAppHeader.roleLabelFor(r, position: p, rawRole: raw);

  test('company_supervisor maps to مشرف', () {
    expect(label(UserRole.admin, raw: 'company_supervisor'), 'مشرف');
    expect(label(UserRole.admin, raw: 'supervisor'), 'مشرف');
    expect(label(UserRole.admin, p: DelegatePosition.supervisor), 'مشرف');
  });

  test('company admin without supervisor role stays مسؤول شركة', () {
    expect(label(UserRole.admin, raw: 'company_admin'), 'مسؤول شركة');
  });

  test('other roles keep sensible labels', () {
    expect(label(UserRole.delegate), 'مندوب');
    expect(label(UserRole.delegate, p: DelegatePosition.promoter), 'مروج');
    expect(label(UserRole.superAdmin), 'سوبر أدمن');
    expect(label(UserRole.hr), 'موارد بشرية (HR)');
    expect(label(UserRole.technicalSupport), 'دعم فني');
  });
}
