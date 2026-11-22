import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// TAS-74: who may submit «إضافة مندوب» from the HR system. The request
/// writes pending delegate placeholders, which the rules allow for company
/// supervisors and company admins but deliberately not for HR. HR users do
/// not see the button, so they never reach a request the rules reject.
bool hrUserCanAddDelegate(Delegate user) => user.role != UserRole.hr;
