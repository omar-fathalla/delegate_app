/// User-facing failure messages for check-in / check-out decisions.
///
/// These are raised from the data layer (like the other attendance failures),
/// so they are kept here as Arabic constants rather than ARB keys.
const String kCheckInOfflineMessage =
    'مفيش اتصال بالإنترنت، الحضور ما اتسجّلش. اتأكد من النت وجرّب تاني.';
const String kCheckOutOfflineMessage =
    'مفيش اتصال بالإنترنت، الانصراف ما اتسجّلش. اتأكد من النت وجرّب تاني.';
const String kCheckInUnknownMessage =
    'النت ضعيف ومقدرناش نتأكد إن الحضور اتسجّل. جرّب تاني، ومش هيتسجّل مرتين.';
const String kCheckOutUnknownMessage =
    'النت ضعيف ومقدرناش نتأكد إن الانصراف اتسجّل. جرّب تاني، ومش هيتسجّل مرتين.';
const String kAlreadyCheckedOutMessage = 'إنت مسجّل انصراف بالفعل.';

/// A check-out within this window after check-in asks for confirmation.
const Duration kEarlyCheckOutConfirmWindow = Duration(minutes: 10);
