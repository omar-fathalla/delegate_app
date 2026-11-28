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

// --- TAS-363: attendance saved on the phone without network ---

/// Message 3.7 (`USER-SCENARIOS/01-delegate-messages.md`). [time] is
/// already formatted (e.g. "9:05 ص").
String offlineCheckInSavedMessage(String time) =>
    'الحضور اتحفظ على الموبايل: مفيش نت دلوقتي، فحفظنا حضورك الساعة $time، '
    'وهيتبعت أول ما النت يرجع. ماتمسحش التطبيق.';

String offlineCheckOutSavedMessage(String time) =>
    'الانصراف اتحفظ على الموبايل: مفيش نت دلوقتي، فحفظنا انصرافك الساعة $time، '
    'وهيتبعت أول ما النت يرجع. ماتمسحش التطبيق.';

const String kOfflineBranchUnknownMessage =
    'مفيش نت، ومكان الفرع ده مش متحفظ على الموبايل. افتح شاشة الحضور مرة وإنت على نت، '
    'أو كلّم المشرف يسجلك.';

const String kOfflineOpenSessionMessage =
    'عندك حضور محفوظ على الموبايل لسه مفتوح. سجّل انصراف الأول.';

const String kOfflineSyncRetryMessage =
    'الحضور المحفوظ على الموبايل لسه ماتبعتش، النت ضعيف. هنحاول تاني لوحدنا.';

/// A record saved offline that the server refused when it was sent.
String offlineRecordRejectedMessage(String serverMessage) =>
    'حضور اتحفظ من غير نت ماتسجلش: $serverMessage';
