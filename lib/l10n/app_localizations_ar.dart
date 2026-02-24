// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'تسهيل - المندوب';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get loginToContinue => 'سجّل دخولك للمتابعة';

  @override
  String get loginSuccessful => 'تم تسجيل الدخول بنجاح!';

  @override
  String get loginButton => 'دخول';

  @override
  String get mobileNumber => 'رقم الموبايل';

  @override
  String get password => 'كلمة المرور';

  @override
  String get motherName => 'اسم الأم';

  @override
  String get enterMobileNumber => 'يرجى إدخال رقم الموبايل';

  @override
  String get enterPassword => 'يرجى إدخال كلمة المرور';

  @override
  String get rememberMe => 'تذكرني';

  @override
  String get home => 'الرئيسية';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get attendance => 'الحضور';

  @override
  String get myProfile => 'ملفي الشخصي';

  @override
  String get personalInformation => 'المعلومات الشخصية';

  @override
  String get delegateId => 'رقم المندوب';

  @override
  String get delegateRole => 'مندوب';

  @override
  String get checkIn => 'تسجيل الحضور';

  @override
  String get checkOut => 'تسجيل الانصراف';

  @override
  String get checkedInSuccessfully => 'تم تسجيل الحضور بنجاح';

  @override
  String get checkedOutSuccessfully => 'تم تسجيل الانصراف بنجاح';

  @override
  String get scanToCheckIn => 'مسح لتسجيل الحضور';

  @override
  String get scanToCheckOut => 'مسح لتسجيل الانصراف';

  @override
  String scanForAction(String action) {
    return 'مسح لـ $action';
  }

  @override
  String pointCameraToQR(String action) {
    return 'وجه الكاميرا نحو QR Code لـ $action';
  }

  @override
  String checkingInAt(String branch) {
    return 'تسجيل حضور في $branch...';
  }

  @override
  String get invalidQRCode => 'QR Code غير صالح. يرجى مسح كود فرع صحيح.';

  @override
  String get currentStatus => 'الحالة الحالية';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'غير متصل';

  @override
  String get active => 'نشط';

  @override
  String inLabel(String time) {
    return 'دخول: $time';
  }

  @override
  String outLabel(String time) {
    return 'خروج: $time';
  }

  @override
  String noRecordsForMonth(String month) {
    return 'لا توجد سجلات حضور لشهر $month';
  }

  @override
  String get recentHistory => 'السجل الأخير';

  @override
  String get noHistoryAvailable => 'لا يوجد سجل حضور';

  @override
  String get somethingWentWrong => 'حدث خطأ';

  @override
  String get unspecifiedBranch => 'غير محدد';

  @override
  String helloUser(String name) {
    return 'مرحباً، $name';
  }

  @override
  String historyInOut(String inTime, String outTime) {
    return 'دخول: $inTime - خروج: $outTime';
  }

  @override
  String get errorGeneral => 'حدث خطأ. يرجى المحاولة مرة أخرى.';

  @override
  String get errorNetwork => 'لا يوجد اتصال بالإنترنت.';

  @override
  String get errorLocation => 'لم يتم العثور على موقعك.';

  @override
  String get errorOutOfRange => 'أنت خارج نطاق موقع العمل.';

  @override
  String get errorMockLocation => 'تم اكتشاف موقع وهمي. لا يمكن تسجيل الحضور.';

  @override
  String get errorAuth => 'بيانات الدخول غير صحيحة.';

  @override
  String get success => 'تمت العملية بنجاح';

  @override
  String get loading => 'جاري التحميل...';

  @override
  String get pendingSync => 'في انتظار المزامنة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get language => 'اللغة';

  @override
  String get changeLanguage => 'تغيير اللغة';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String languageChangedTo(String language) {
    return 'تم تغيير اللغة إلى $language';
  }

  @override
  String duration(String hours, String minutes) {
    return 'المدة: $hours س $minutes د';
  }

  @override
  String get inProgress => 'جاري...';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String get phoneNumber => 'رقم الهاتف';

  @override
  String get birthDate => 'تاريخ الميلاد';

  @override
  String get cityLabel => 'المدينة';

  @override
  String get organizationAndCompany => 'المنظمة والشركة';

  @override
  String get organizationLabel => 'المنظمة';

  @override
  String get companyLabel => 'الشركة';

  @override
  String get positionLabel => 'المنصب';

  @override
  String get documents => 'المستندات';

  @override
  String get requestHistory => 'سجل الطلبات';

  @override
  String get personalPhoto => 'الصورة الشخصية';

  @override
  String get nationalId => 'رقم الهوية الوطنية';

  @override
  String get authorizationLetter => 'خطاب التفويض';

  @override
  String get insuranceLetter => 'خطاب التأمين';

  @override
  String get healthCertificate => 'شهادة صحية';

  @override
  String get paymentReceipt => 'إيصال الدفع';

  @override
  String get pendingStatus => 'قيد الانتظار';

  @override
  String uploadedOn(String date) {
    return 'تم التحميل: $date';
  }

  @override
  String get clickToView => 'انقر للعرض';

  @override
  String receiptCode(String code) {
    return 'رمز الإيصال: $code';
  }

  @override
  String get noRequestsYet => 'لا توجد طلبات حتى الآن';

  @override
  String get approvedStatus => 'مقبول';

  @override
  String get rejectedStatus => 'مرفوض';

  @override
  String get noDocumentsUploaded => 'لا توجد مستندات مرفوعة';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get gender => 'الجنس';

  @override
  String get male => 'ذكر';

  @override
  String get female => 'أنثى';

  @override
  String get joinDate => 'تاريخ الانضمام';

  @override
  String get employmentDetails => 'تفاصيل العمل';

  @override
  String get statusReason => 'سبب الحالة';

  @override
  String get profileComplete => 'الملف مكتمل';

  @override
  String get profileIncomplete => 'الملف غير مكتمل';

  @override
  String reviewedBy(String name) {
    return 'تمت المراجعة بواسطة: $name';
  }

  @override
  String get notProvidedStatus => 'لم يتم تقديمها';

  @override
  String get adminDashboard => 'لوحة الإدارة';

  @override
  String get addBranch => 'إضافة فرع جديد';

  @override
  String get branchName => 'اسم الفرع';

  @override
  String get branchLocation => 'موقع الفرع';

  @override
  String get geofenceRadius => 'نطاق الحضور (بالأمتار)';

  @override
  String get saveBranch => 'حفظ الفرع';

  @override
  String get branchAddedSuccessfully => 'تمت إضافة الفرع بنجاح';

  @override
  String get pleaseEnterBranchName => 'يرجى إدخال اسم الفرع';

  @override
  String get pleaseSelectLocation => 'يرجى تحديد الموقع على الخريطة';

  @override
  String get searchCityOrRegion => 'ابحث عن مدينة أو منطقة...';

  @override
  String get branches => 'الفروع';

  @override
  String get admin => 'المدير';

  @override
  String get myLocation => 'موقعي الحالي';

  @override
  String get locationServicesDisabled => 'خدمات الموقع معطلة.';

  @override
  String get locationPermissionDenied => 'تم رفض صلاحية الموقع.';

  @override
  String get errorFetchingLocation => 'حدث خطأ أثناء جلب الموقع.';

  @override
  String get branchDetails => 'تفاصيل الفرع';

  @override
  String get downloadQR => 'تحميل كصورة';

  @override
  String get qrSavedToGallery => 'تم حفظ رمز QR في المعرض بنجاح!';

  @override
  String get editName => 'تعديل الاسم';

  @override
  String get deleteBranch => 'مسح الفرع';

  @override
  String get deleteBranchConfirmation =>
      'هل أنت متأكد من مسح هذا الفرع بالكامل؟';

  @override
  String get branchDeletedSuccessfully => 'تم مسح الفرع بنجاح.';

  @override
  String get saveChanges => 'حفظ التعديلات';

  @override
  String get networkStatusOffline => 'غير متصل بالشبكة';

  @override
  String get networkStatusOnline => 'متصل بالشبكة';

  @override
  String get showPassword => 'إظهار كلمة المرور';

  @override
  String get hidePassword => 'إخفاء كلمة المرور';

  @override
  String get close => 'إغلاق';
}
