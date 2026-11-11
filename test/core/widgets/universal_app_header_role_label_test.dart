import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String label(UserRole r, {DelegatePosition? p, String? raw}) =>
      UniversalAppHeader.roleLabelFor(r, position: p, rawRole: raw);

  test('company admin and company supervisor share one label', () {
    expect(label(UserRole.admin, raw: 'company_supervisor'), 'مشرف الشركة');
    expect(label(UserRole.admin, raw: 'supervisor'), 'مشرف الشركة');
    expect(label(UserRole.admin, raw: 'admin'), 'مشرف الشركة');
    expect(label(UserRole.admin, raw: 'company_admin'), 'مشرف الشركة');
    expect(
      label(UserRole.admin, p: DelegatePosition.supervisor),
      'مشرف الشركة',
    );
    expect(label(UserRole.admin), 'مشرف الشركة');
  });

  test('field-supervisor job title on a delegate stays مشرف', () {
    expect(label(UserRole.delegate, p: DelegatePosition.supervisor), 'مشرف');
  });

  test('other roles keep sensible labels', () {
    expect(label(UserRole.delegate), 'مندوب');
    expect(label(UserRole.delegate, p: DelegatePosition.promoter), 'مروج');
    expect(label(UserRole.superAdmin), 'سوبر أدمن');
    expect(label(UserRole.hr), 'موارد بشرية (HR)');
    expect(label(UserRole.technicalSupport), 'دعم فني');
  });
}
