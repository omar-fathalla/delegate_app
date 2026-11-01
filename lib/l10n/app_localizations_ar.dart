// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'تسهيل';

  @override
  String get delegateApp => 'تطبيق الموظفين';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get loginToContinue => 'مرحباً بعودتك، يرجى إدخال بياناتك';

  @override
  String get loginSuccessful => 'تم تسجيل الدخول بنجاح!';

  @override
  String get loginButton => 'تسجيل الدخول';

  @override
  String get mobileNumber => 'رقم الجوال';

  @override
  String get password => 'كلمة المرور';

  @override
  String get motherName => 'اسم الأم';

  @override
  String get enterMobileNumber => 'يرجى إدخال رقم الموبايل';

  @override
  String get enterPassword => 'يرجى إدخال كلمة المرور';

  @override
  String get nationalIdNumber => 'الرقم القومي';

  @override
  String get enterNationalId => 'يرجى إدخال الرقم القومي';

  @override
  String get invalidNationalId => 'يجب أن يتكون الرقم القومي من 14 رقمًا';

  @override
  String get invalidMobileNumber => 'يرجى إدخال رقم موبايل صحيح';

  @override
  String get loginNationalIdHelp =>
      'المندوب يسجّل الدخول بالرقم القومي. باقي الأدوار تستخدم كلمة المرور.';

  @override
  String get invalidLoginCredentials =>
      'رقم الهاتف أو الرقم القومي أو كلمة المرور غير صحيح.';

  @override
  String get delegateAccountInactive =>
      'هذا الحساب قيد المراجعة أو موقوف. يرجى التواصل مع مسؤول الشركة.';

  @override
  String get tooManyLoginAttempts =>
      'تم تجاوز عدد المحاولات. يرجى المحاولة لاحقاً.';

  @override
  String get loginTemporarilyUnavailable =>
      'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.';

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
  String get scanQrInstruction =>
      'اعمل اسكان لـ QR Code المتواجد في مكتب التسويق.';

  @override
  String scanForAction(String action) {
    return 'امسح ل$action';
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
  String get companies => 'الشركات';

  @override
  String get search => 'بحث';

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
  String get electronicPaymentReceipt => 'إيصال دفع إلكتروني';

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
  String get addBranch => 'إضافة فرع';

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
  String get roleBranchMarketing => 'تسويق الفروع';

  @override
  String get roleBranchesMarketingManager => 'مدير تسويق الفروع';

  @override
  String get roleBranchesMarketingMgrShort => 'مدير تسويق فروع';

  @override
  String get roleMarketingPromotion => 'تسويق العروض';

  @override
  String get branchMarketingFollowUp => 'متابعة تسويق الفروع';

  @override
  String get branchMarketingCoordination => 'تنسيق تسويق الفروع';

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
  String get editBranch => 'تعديل الفرع';

  @override
  String get branchUpdatedSuccessfully => 'تم تعديل الفرع بنجاح.';

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
  String get noAccountContact => 'ليس لديك حساب؟ تواصل على الرقم التالي';

  @override
  String get noAccountTitle => 'ليس لديك حساب؟';

  @override
  String get noAccountSubtitle => 'تواصل على الرقم التالي';

  @override
  String get contactNumber => '01211857725';

  @override
  String get darkMode => 'الوضع الداكن';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get helpCenter => 'مركز المساعدة';

  @override
  String version(String version) {
    return 'مندوب تسهيل - الإصدار $version';
  }

  @override
  String get account => 'الحساب';

  @override
  String get privacyPolicyDesc =>
      'توضح سياسة الخصوصية هذه كيف نقوم بجمع، استخدام، والإفصاح عن معلوماتك الشخصية عند استخدامك لخدمات المندوب. نحن ملتزمون بحماية خصوصيتك وضمان التعامل مع بياناتك بشكل آمن.';

  @override
  String get locationData => 'بيانات الموقع';

  @override
  String get locationDataDesc =>
      'يجمع تطبيقنا بيانات الموقع لتمكين تتبع الطلبات في الوقت الفعلي ومطابقة المناديب مع الطلبات القريبة حتى عندما يكون التطبيق مغلقاً أو غير مستخدم. هذه البيانات أساسية للوظيفة الأساسية لخدمتنا.';

  @override
  String get cameraAccess => 'الوصول للكاميرا';

  @override
  String get cameraAccessDesc =>
      'نطلب الوصول إلى الكاميرا للسماح لك بالتقاط صور الفواتير، الطرود أو إثباتات التوصيل. يتم التقاط الصور فقط عندما تستخدم ميزة الكاميرا بوضوح داخل التطبيق.';

  @override
  String get dataSecurity => 'أمن البيانات';

  @override
  String get dataSecurityDesc =>
      'نطبّق معايير الأمان المعتمدة في الصناعة لحماية بياناتك. نحن لا نبيع بياناتك الشخصية. تتم مشاركة معلوماتك فقط مع الشركاء المعتمدين لمعالجة الخدمات.';

  @override
  String get contactUs => 'تواصل معنا';

  @override
  String get website => 'الموقع الإلكتروني';

  @override
  String get emailAddress => 'البريد الإلكتروني';

  @override
  String get egyptOffice => 'مكتب مصر';

  @override
  String get uaeOffice => 'مكتب الإمارات';

  @override
  String get swPointWebsite => 'https://sw-point.com/';

  @override
  String get swPointEmail => 'support@sw-point.com';

  @override
  String get swPointEgyptPhone => 'Alexandria, Egypt +20 121 185 7725';

  @override
  String get swPointUaePhone =>
      'United Arab Emirates WhatsApp: +971 55 871 5615';

  @override
  String get createAdmin => 'إنشاء أدمن';

  @override
  String get adminName => 'اسم الأدمن';

  @override
  String get adminPhone => 'رقم الهاتف';

  @override
  String get adminEmail => 'البريد الإلكتروني';

  @override
  String get pleaseEnterAdminName => 'يرجى إدخال اسم الأدمن';

  @override
  String get pleaseEnterAdminPhone => 'يرجى إدخال رقم الهاتف';

  @override
  String get pleaseEnterAdminEmail => 'يرجى إدخال البريد الإلكتروني';

  @override
  String get invalidPhoneNumber => 'رقم هاتف غير صالح';

  @override
  String get invalidEmail => 'بريد إلكتروني غير صالح';

  @override
  String get adminCreatedSuccessfully =>
      'تم إنشاء حساب الأدمن بنجاح! تم إرسال بريد التفعيل.';

  @override
  String get manageAdmins => 'إدارة الأدمن';

  @override
  String get noAdminsFound => 'لا يوجد أدمن';

  @override
  String get suspended => 'موقوف';

  @override
  String get editAdmin => 'تعديل';

  @override
  String get deleteAdmin => 'حذف';

  @override
  String get suspendAdmin => 'إيقاف';

  @override
  String get activateAdmin => 'تفعيل';

  @override
  String get deleteAdminConfirmation =>
      'هل أنت متأكد من حذف هذا الأدمن؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get companyDelegates => 'المناديب';

  @override
  String get viewAttendance => 'عرض الحضور';

  @override
  String get noDelegatesFound => 'لا يوجد مناديب';

  @override
  String get viewProfileData => 'عرض البيانات';

  @override
  String get addDelegate => 'إضافة مندوب';

  @override
  String get addDelegateViaWeb => 'إضافة عبر الموقع';

  @override
  String get tasks => 'المهام';

  @override
  String get todayOverview => 'نظرة عامة اليوم';

  @override
  String get totalDelegates => 'إجمالي المناديب';

  @override
  String get checkedInToday => 'الحاضرون اليوم';

  @override
  String get absentToday => 'الغائبون';

  @override
  String get addTask => 'إضافة مهمة';

  @override
  String get taskTitle => 'عنوان المهمة';

  @override
  String get taskDescription => 'وصف المهمة';

  @override
  String get taskPriority => 'الأولوية';

  @override
  String get high => 'عالية';

  @override
  String get medium => 'متوسطة';

  @override
  String get low => 'منخفضة';

  @override
  String get taskDueDate => 'تاريخ التنفيذ';

  @override
  String get assignTo => 'تعيين إلى';

  @override
  String get allDelegates => 'جميع المناديب';

  @override
  String get createTask => 'إنشاء مهمة';

  @override
  String get taskCreatedSuccessfully => 'تم إنشاء المهمة بنجاح';

  @override
  String get taskUpdatedSuccessfully => 'تم تحديث المهمة بنجاح';

  @override
  String get noTasksFound => 'لا توجد مهام حالياً';

  @override
  String get taskStatus => 'حالة المهمة';

  @override
  String get taskPending => 'معلقة';

  @override
  String get taskInProgress => 'قيد التنفيذ';

  @override
  String get taskCompleted => 'منجزة';

  @override
  String get all => 'الكل';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String get taskCancelled => 'ملغاة';

  @override
  String get taskDetails => 'تفاصيل المهمة';

  @override
  String get taskSchedule => 'الجدول الزمني';

  @override
  String get selectDelegate => 'اختر المندوب';

  @override
  String get errorFieldRequired => 'هذا الحقل مطلوب';

  @override
  String get addTaskToGetStarted => 'أضف مهمة للبدء';

  @override
  String get myTasks => 'مهامي';

  @override
  String get noTasksYet => 'لا توجد مهامي بعد';

  @override
  String get complete => 'إكمال';

  @override
  String get delete => 'حذف';

  @override
  String get deleteTask => 'حذف المهمة';

  @override
  String get deleteTaskConfirmation =>
      'هل أنت متأكد من رغبتك في حذف هذه المهمة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get notes => 'الملاحظات';

  @override
  String get tasksSummary => 'ملخص المهام';

  @override
  String get total => 'الإجمالي';

  @override
  String get searchDelegates => 'البحث عن مندوب...';

  @override
  String get filterByStatus => 'تصفية حسب الحالة';

  @override
  String get noDelegateSearchResults => 'لا توجد نتائج مطابقة لبحثك';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get noNotifications => 'لا توجد إشعارات';

  @override
  String get markAllRead => 'تعليم الكل كمقروء';

  @override
  String get newNotification => 'إشعار جديد';

  @override
  String get searchCompanies => 'البحث عن الشركات';

  @override
  String get searchCompaniesHint => 'ابحث عن الشركات باستخدام كود الشركة';

  @override
  String get enterCompanyCode => 'أدخل كود الشركة';

  @override
  String get clear => 'مسح';

  @override
  String get noCompaniesFound => 'لا توجد شركات';

  @override
  String get searchQuery => 'البحث';

  @override
  String get errorOccurred => 'حدث خطأ';

  @override
  String get tryAgain => 'حاول مرة أخرى';

  @override
  String get manageMarketing => 'إدارة موظفي التسويق';

  @override
  String get noMarketingEmployeesFound => 'لا يوجد موظفي تسويق';

  @override
  String get searchByPhone => 'البحث برقم الموبايل...';

  @override
  String get filterByOrganization => 'تصفية حسب المنظمة';

  @override
  String get allOrganizations => 'جميع المنظمات';

  @override
  String get marketingEmployee => 'موظف تسويق';

  @override
  String get editMarketingEmployee => 'تعديل بيانات الموظف';

  @override
  String get deleteMarketingEmployee => 'حذف الموظف';

  @override
  String get deleteMarketingEmployeeConfirmation =>
      'هل أنت متأكد من حذف هذا الموظف؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get suspendMarketingEmployee => 'إيقاف الموظف';

  @override
  String get activateMarketingEmployee => 'تفعيل الموظف';

  @override
  String get employeeSuspended => 'تم إيقاف الموظف';

  @override
  String get employeeActivated => 'تم تفعيل الموظف';

  @override
  String get employeeDeleted => 'تم حذف الموظف بنجاح';

  @override
  String get employeeUpdated => 'تم تحديث بيانات الموظف بنجاح';

  @override
  String get employeeName => 'اسم الموظف';

  @override
  String get employeePhone => 'رقم الهاتف';

  @override
  String get employeeEmail => 'البريد الإلكتروني';

  @override
  String get organization => 'المنظمة';

  @override
  String get forgotCheckoutTitle => 'تنبيه حضور معلق';

  @override
  String forgotCheckoutMessage(String oldBranch, String newBranch) {
    return 'لديك حضور معلق في $oldBranch. هل تريد تسجيل الانصراف منه وتسجيل الحضور في $newBranch؟';
  }

  @override
  String previousDayCheckoutMessage(String oldBranch, String newBranch) {
    return 'لديك حضور معلق من يوم سابق في $oldBranch. سيتم إغلاقه وتسجيل حضورك لليوم في $newBranch.';
  }

  @override
  String get confirmAction => 'تأكيد';

  @override
  String get photoPermissions => 'أذونات التصوير';

  @override
  String get photoPermissionsDesc =>
      'إدارة أذونات التصوير ومتابعة تقارير الصور';

  @override
  String get supervisor => 'مشرف';

  @override
  String supervisorUser(String name) {
    return 'مشرف: $name';
  }

  @override
  String adminUser(String name) {
    return 'المدير: $name';
  }

  @override
  String get paymentReceiptsReport => 'تقرير إيصالات الدفع الإلكتروني';

  @override
  String get uploadsCount => 'عدد الإيصالات';

  @override
  String get totalUploadedReceipts => 'إجمالي الإيصالات';

  @override
  String get companiesWithUploads => 'الشركات المفعلة';

  @override
  String get receiptsReport => 'تقرير إيصالات الدفع الإلكتروني';

  @override
  String get accountant => 'إدارة الحسابات';

  @override
  String get accountantDashboard => 'لوحة تحكم الحسابات والماليات';

  @override
  String get financialReports => 'التقارير المالية';

  @override
  String get paymentReceipts => 'إيصالات السداد';

  @override
  String get subscriptionRequests => 'طلبات الاشتراك';

  @override
  String get walletsManagement => 'إدارة المحافظ';

  @override
  String get violationsPolicy => 'لائحة المخالفات';

  @override
  String get myViolations => 'مخالفاتي';

  @override
  String get switchOrganization => 'تبديل المنظمة';

  @override
  String get manageOrganizationsChains => 'إدارة المنظمات والسلاسل';

  @override
  String get delegateSubscriptionsMenu => 'اشتراكات واعتماد المندوبين';

  @override
  String get mainMenu => 'القائمة الرئيسية';

  @override
  String get navRequests => 'طلباتي';

  @override
  String get navPhotoReports => 'تقارير الصور';

  @override
  String get roleDelegate => 'مندوب';

  @override
  String get roleSupervisor => 'مشرف';

  @override
  String get roleCompanyAdmin => 'مسؤول شركة';

  @override
  String get roleSuperAdmin => 'سوبر أدمن';

  @override
  String get roleOrgAdmin => 'أدمن منظمة';

  @override
  String get roleTechSupport => 'دعم فني';

  @override
  String get roleMarketing => 'تسويق';

  @override
  String get roleHr => 'موارد بشرية (HR)';

  @override
  String get defaultUserName => 'مستخدم';

  @override
  String get offlineBannerTitle => 'أنت غير متصل';

  @override
  String offlineLastSync(Object time) {
    return 'آخر تحديث $time';
  }

  @override
  String get offlineNoSyncYet => 'سيتم التحديث عند عودة الاتصال';

  @override
  String get offlineNotifications =>
      'لا يمكن تحميل الإشعارات بدون إنترنت. اتصل بالإنترنت وحاول مرة أخرى.';

  @override
  String get refreshFailed => 'تعذّر التحديث. تحقق من الاتصال وحاول مرة أخرى.';

  @override
  String get startPhotosCta => 'ابدأ التصوير';

  @override
  String get switchOn => 'مفعّل';

  @override
  String get switchOff => 'متوقف';

  @override
  String get whatsNewTitle => 'ما الجديد؟';

  @override
  String releaseVersionDate(Object version, Object date) {
    return 'الإصدار $version – $date';
  }

  @override
  String get feedbackTypeFeature => 'فكرة تطويرية';

  @override
  String get feedbackTypeBug => 'الإبلاغ عن مشكلة';

  @override
  String get feedbackTypeQuestion => 'استفسار عام';

  @override
  String get feedbackTypeImprovement => 'تحسين';

  @override
  String get feedbackTypeOther => 'أخرى';

  @override
  String get reqTitle => 'طلباتي';

  @override
  String get refreshAction => 'تحديث';

  @override
  String get newRequest => 'طلب جديد';

  @override
  String get reqEmptyAll => 'لا توجد طلبات بعد';

  @override
  String get reqEmptyFilter => 'لا توجد طلبات بهذه الحالة';

  @override
  String get reqEmptyHint => 'اضغط «طلب جديد» لإرسال طلبك إلى المشرف';

  @override
  String get annualLeaveBalance => 'رصيد الإجازات السنوي';

  @override
  String get weeklyOffPlan => 'نظام الراحة الأسبوعية';

  @override
  String get daysOffPerMonth => '4 أيام راحة شهريًا';

  @override
  String get weeklyDayOff => 'راحة أسبوعية';

  @override
  String get oneDayEvery7 => 'يوم كل 7 أيام';

  @override
  String get hourlyPermission => 'استئذان بالساعة';

  @override
  String get availableLabel => 'متاح';

  @override
  String get annualBalance21 => 'الرصيد السنوي: 21 يومًا';

  @override
  String get onceActivated => 'بعد التفعيل';

  @override
  String get filterAll => 'الكل';

  @override
  String get statusPendingReview => 'قيد المراجعة';

  @override
  String get statusApprovedPl => 'مقبولة';

  @override
  String get statusRejectedPl => 'مرفوضة';

  @override
  String get leaveSick => 'إجازة مرضية';

  @override
  String get leaveEmergency => 'إجازة عارضة';

  @override
  String get excuseLate => 'عذر تأخير';

  @override
  String get excuseEarlyLeave => 'إذن انصراف مبكر';

  @override
  String get excuseAbsence => 'غياب بعذر';

  @override
  String get leaveUnpaid => 'إجازة بدون أجر';

  @override
  String get leaveAnnual => 'إجازة اعتيادية';

  @override
  String get statusApproved => 'مقبول';

  @override
  String get statusRejected => 'مرفوض';

  @override
  String get statusPending => 'قيد المراجعة';

  @override
  String get previewAttachment => 'معاينة المرفق';

  @override
  String get cancelRequest => 'إلغاء الطلب';

  @override
  String get cancelRequestConfirm => 'هل تريد إلغاء هذا الطلب؟';

  @override
  String get keepRequest => 'تراجع';

  @override
  String get yesCancel => 'نعم، إلغاء';

  @override
  String get requestCancelled => 'تم إلغاء الطلب';

  @override
  String get requestType => 'نوع الطلب';

  @override
  String get weeklyPlanAvailableInfo =>
      'المتاح لك حاليًا: استئذان بالساعة، أو غياب بعذر، أو إجازة بدون أجر.';

  @override
  String remainingDays(int count) {
    return 'المتبقي: $count يوم';
  }

  @override
  String usedDays(int count) {
    return 'المستهلك: $count يوم';
  }

  @override
  String totalQuotaDays(int count) {
    return 'إجمالي الرصيد: $count يوم';
  }

  @override
  String forYear(int year) {
    return 'لعام $year';
  }

  @override
  String reasonLabel(Object reason) {
    return 'السبب: $reason';
  }

  @override
  String rejectReasonLabel(Object reason) {
    return 'سبب الرفض: $reason';
  }

  @override
  String approvedBy(Object name) {
    return 'اعتمده: $name';
  }

  @override
  String get homeSupervisorsTitle => 'المشرفون';

  @override
  String homeGreeting(Object firstName) {
    return 'أهلًا، $firstName';
  }

  @override
  String get roleFieldDelegate => 'مندوب ميداني';

  @override
  String get roleFieldSupervisor => 'مشرف ميداني';

  @override
  String get homeCoreDuties => 'مهامك الأساسية';

  @override
  String get homeDutyAttendance => 'سجّل حضورك وانصرافك من موقع الفرع.';

  @override
  String get homeDutyTasks => 'نفّذ مهامك اليومية وتابِعها.';

  @override
  String get homeDutyPhotos =>
      'صوّر العروض والعلامات التجارية في الهايبر ماركت والفروع.';

  @override
  String get companySupervisor => 'مشرف الشركة';

  @override
  String supervisorOfCompany(Object companyName) {
    return 'مشرف – $companyName';
  }

  @override
  String get assignedCompanySupervisor => 'مشرف الشركة المنتدبة';

  @override
  String get callAction => 'اتصال';

  @override
  String get offerPhotosTitle => 'تصوير العروض';

  @override
  String get offerPhotosSubtitle =>
      'صوّر العروض المعتمدة وارفعها من داخل الهايبر ماركت';

  @override
  String homeAttendanceSummary(Object monthName) {
    return 'الحضور والغياب – $monthName';
  }

  @override
  String get detailsAction => 'التفاصيل';

  @override
  String get statAttended => 'حضور';

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: '0 يوم',
    );
    return '$_temp0';
  }

  @override
  String get statAbsent => 'غياب';

  @override
  String get statDaysOff => 'إجازة';

  @override
  String leavesOfFour(Object count) {
    return '$count من 4 أيام';
  }

  @override
  String get workPolicyNote =>
      '26 يوم عمل شهريًا • 4 أيام راحة لا تُحسب غيابًا';

  @override
  String get chainGomlaMarket => 'جملة ماركت';

  @override
  String get chainFathallaMarket => 'فتح الله ماركت';

  @override
  String get chainZahranMarket => 'زهران ماركت';

  @override
  String get recentBranchActivity => 'آخر الفروع والنشاط الميداني';

  @override
  String get viewLog => 'عرض السجل';

  @override
  String get unknownBranch => 'فرع غير محدد';

  @override
  String get onShift => 'قيد العمل';

  @override
  String durationHm(Object hours, Object minutes) {
    return '$hours س $minutes د';
  }

  @override
  String branchLabel(Object cleanBranchName) {
    return 'الفرع: $cleanBranchName';
  }

  @override
  String get homeRequestsSubtitle => 'قدّم طلبات الإجازة والأعذار وتابع رصيدك';

  @override
  String companySupervisorWithName(Object companyName) {
    return 'مشرف الشركة ($companyName)';
  }

  @override
  String errorWithMessage(Object error) {
    return 'خطأ: $error';
  }

  @override
  String noSupervisorForCompany(Object companyUID) {
    return 'لا يوجد مشرف مسجّل لهذه الشركة حاليًا\n(Company ID: $companyUID)';
  }

  @override
  String pendingCountBadge(Object count) {
    return '$count قيد المراجعة';
  }

  @override
  String get orgMarketing => 'إدارة التسويق';

  @override
  String get orgAdminPanel => 'لوحة الإدارة';

  @override
  String get orgAccounting => 'الحسابات والمالية';

  @override
  String switchedToOrg(Object orgLabel) {
    return 'تم التبديل إلى: $orgLabel';
  }

  @override
  String get unknownOrganization => 'منظمة غير محددة';

  @override
  String get alreadyInOrg => 'أنت تعمل ضمن هذه المنظمة بالفعل.';

  @override
  String get logoutAction => 'تسجيل الخروج';

  @override
  String get logoutConfirm =>
      'تسجيل الخروج؟\nستُحفظ بياناتك المحلية قبل الخروج.';

  @override
  String logoutFailed(Object error) {
    return 'تعذّر تسجيل الخروج: $error';
  }

  @override
  String get backAction => 'رجوع';

  @override
  String get sendFeedback => 'إرسال ملاحظات';

  @override
  String get rateTheApp => 'قيّم التطبيق';

  @override
  String get manageFeedback => 'إدارة الملاحظات';

  @override
  String get myFeedback => 'ملاحظاتي';

  @override
  String get photoPermissions2 => 'أذونات التصوير';

  @override
  String get appColor => 'لون التطبيق';

  @override
  String get attCheckingZone => 'جارٍ فحص النطاق...';

  @override
  String get attVerifyingCoords =>
      'يتم الآن التحقق من إحداثياتك والمسافة للفرع';

  @override
  String get attInsideZone => 'أنت داخل نطاق العمل';

  @override
  String attWithinBranchRange(Object branch) {
    return 'داخل نطاق فرع $branch';
  }

  @override
  String get attWithinAllowedRange => 'داخل النطاق المسموح';

  @override
  String get attOutsideZone => 'خارج نطاق العمل';

  @override
  String attMoveCloserTo(Object branch) {
    return 'اقترب من فرع $branch لتسجيل الحضور';
  }

  @override
  String get attOutsideApprovedBranches => 'خارج نطاق الفروع المعتمدة';

  @override
  String distanceKmM(Object km, Object meters) {
    return '$km كم ($meters م)';
  }

  @override
  String get previousMonth => 'الشهر السابق';

  @override
  String get currentMonth => 'الشهر الحالي';

  @override
  String get nextMonth => 'الشهر التالي';

  @override
  String get attWorkPolicyNote => '26 يوم عمل • 4 أيام راحة لا تُحسب غيابًا';

  @override
  String distanceLabel(Object formattedDistance) {
    return 'المسافة: $formattedDistance';
  }

  @override
  String radiusLabel(Object allowedRadius) {
    return 'النطاق: $allowedRadius م';
  }

  @override
  String get recheckLocation => 'إعادة فحص الموقع';

  @override
  String get activeChain => 'السلسلة الحالية';

  @override
  String get allChains => 'كل السلاسل';

  @override
  String attNoSessionsInChain(Object chain) {
    return 'لا توجد سجلات حضور في $chain هذا الشهر';
  }

  @override
  String attDaysInOtherChains(Object count) {
    return 'لديك $count يوم حضور مسجّل في السلاسل الأخرى.';
  }

  @override
  String get showAllChains => 'عرض جميع السلاسل';

  @override
  String get attAutoClosedNote =>
      'أُغلق الانصراف تلقائيًا بعد 9 ساعات من بداية الوردية لعدم تسجيله يدويًا';

  @override
  String get autoClosed9h => 'إغلاق تلقائي (9 س)';

  @override
  String get checkOut2 => 'تسجيل الانصراف';

  @override
  String get attCheckingLocation => 'جارٍ فحص الموقع...';

  @override
  String get checkIn2 => 'تسجيل الحضور';

  @override
  String get noBranchesForOrgYet => 'لا توجد فروع مسجلة لهذه المؤسسة حاليًا.';

  @override
  String get noBranchesForOrg => 'لا توجد فروع مسجلة لهذه المؤسسة.';

  @override
  String attYouAreWithinBranch(Object branch) {
    return 'أنت داخل نطاق فرع $branch';
  }

  @override
  String get attMoveCloser => 'اقترب من الفرع لتسجيل الحضور';

  @override
  String get attOutsideApproved => 'أنت خارج نطاق الفروع المعتمدة';

  @override
  String get attCheckInSavedOffline =>
      'سُجّل الحضور على الجهاز، وستتم المزامنة عند الاتصال بالإنترنت.';

  @override
  String get attCheckOutSavedOffline =>
      'سُجّل الانصراف على الجهاز، وستتم المزامنة عند الاتصال بالإنترنت.';

  @override
  String get syncDone => 'تمت المزامنة';

  @override
  String get syncFailed => 'فشلت المزامنة';

  @override
  String attDelegateOfCompany(Object companyName) {
    return 'مندوب – $companyName';
  }

  @override
  String get attendanceLog => 'سجل الحضور';

  @override
  String distanceMeters(Object meters) {
    return '$meters م';
  }

  @override
  String get attLocatingYou => 'جارٍ تحديد موقعك والتحقق من الفروع...';

  @override
  String get attLocationUnavailable => 'تعذّر تحديد موقعك. فعّل GPS.';

  @override
  String attInsideBranchWithDistance(Object branch, Object meters) {
    return 'أنت داخل نطاق فرع $branch ($meters متر)';
  }

  @override
  String attOutsideBranchWithRadius(Object meters, Object radius) {
    return 'أنت خارج نطاق الفرع ($meters متر). النطاق المسموح: $radius متر.';
  }

  @override
  String get attEnsureGps => 'تأكد من تشغيل GPS وانتظر حتى يُحدَّد موقعك.';

  @override
  String metersValue(Object value) {
    return '$value متر';
  }

  @override
  String attCannotActOutside(Object action, Object distance) {
    return 'لا يمكنك $action وأنت خارج نطاق الفرع ($distance). كن داخل الفرع.';
  }

  @override
  String attCheckingInAt(Object branchName) {
    return 'تسجيل الحضور في $branchName...';
  }

  @override
  String get locationServicesOff => 'خدمات الموقع متوقفة. فعّلها.';

  @override
  String get locationPermissionDenied2 => 'تم رفض إذن الوصول للموقع';

  @override
  String get locationPermissionDeniedForever => 'إذن الموقع مرفوض بشكل دائم.';

  @override
  String get fakeGpsDetected =>
      'تم اكتشاف استخدام برنامج لتزييف الموقع الجغرافي (Fake GPS). يرجى إيقاف التطبيق لتسجيل الحضور والانصراف.';

  @override
  String get locationTimeout =>
      'انتهى الوقت ولم نتمكن من تحديد موقعك. تأكد من تفعيل GPS وأنك في مكان مفتوح.';

  @override
  String get locationError => 'حدث خطأ أثناء تحديد الموقع.';

  @override
  String get trustedTime => 'وقت موثوق';

  @override
  String get attActionCheckIn => 'تسجيل الحضور';

  @override
  String get attActionCheckOut => 'تسجيل الانصراف';

  @override
  String get userNotFound => 'لم يتم العثور على المستخدم';

  @override
  String get accountNotIdentified => 'تعذّر تحديد الحساب';

  @override
  String get profilePhotoUpdated => 'تم تحديث الصورة الشخصية';

  @override
  String photoUploadFailed(Object error) {
    return 'تعذّر رفع الصورة: $error';
  }

  @override
  String get profilePhotoDeleted => 'تم حذف الصورة الشخصية';

  @override
  String photoDeleteFailed(Object error) {
    return 'تعذّر حذف الصورة: $error';
  }

  @override
  String get profilePhoto => 'الصورة الشخصية';

  @override
  String get takePhotoCamera => 'التقط صورة بالكاميرا';

  @override
  String get chooseFromGallery => 'اختر من معرض الصور';

  @override
  String get removeCurrentPhoto => 'حذف الصورة الحالية';

  @override
  String get roleSuperAdmin2 => 'المشرف العام';

  @override
  String get roleTechSupport2 => 'الدعم الفني';

  @override
  String get roleOrgAdmin2 => 'مسؤول المنظمة';

  @override
  String get roleCompanyAdmin2 => 'مشرف الشركة';

  @override
  String get roleHrOfficer => 'مسؤول موارد بشرية';

  @override
  String get roleAccountant => 'إدارة الحسابات';

  @override
  String get roleMarketing2 => 'التسويق والعلاقات';

  @override
  String get personalInfo => 'المعلومات الشخصية';

  @override
  String get nameLabel => 'الاسم';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get phoneNumberLabel => 'رقم الجوال';

  @override
  String get securitySection => 'الأمان';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String editField(Object label) {
    return 'تعديل $label';
  }

  @override
  String get nameUpdated => 'تم تحديث الاسم';

  @override
  String get emailUpdated => 'تم تحديث البريد الإلكتروني';

  @override
  String get phoneUpdated => 'تم تحديث رقم الجوال';

  @override
  String get editName2 => 'تعديل الاسم';

  @override
  String get editEmail => 'تعديل البريد الإلكتروني';

  @override
  String get editPhone => 'تعديل رقم الجوال';

  @override
  String get fullName2 => 'الاسم الكامل';

  @override
  String get newEmail => 'البريد الإلكتروني الجديد';

  @override
  String get newPhone => 'رقم الجوال الجديد';

  @override
  String get enterName => 'أدخل الاسم';

  @override
  String get enterEmail => 'أدخل البريد الإلكتروني';

  @override
  String get enterPhone => 'أدخل رقم الجوال';

  @override
  String get nameMin3 => 'يجب ألا يقل الاسم عن 3 أحرف';

  @override
  String get invalidEmail2 => 'أدخل بريدًا إلكترونيًا صحيحًا';

  @override
  String get invalidPhone => 'أدخل رقم جوال صحيحًا';

  @override
  String get saveAction => 'حفظ';

  @override
  String get passwordChanged => 'تم تغيير كلمة المرور';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get enterCurrentPassword => 'أدخل كلمة المرور الحالية';

  @override
  String get newPassword => 'كلمة المرور الجديدة';

  @override
  String get enterNewPassword => 'أدخل كلمة المرور الجديدة';

  @override
  String get passwordMin6 => 'يجب ألا تقل كلمة المرور عن 6 أحرف';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور';

  @override
  String get enterConfirmPassword => 'أكّد كلمة المرور';

  @override
  String get passwordsDontMatch => 'كلمتا المرور غير متطابقتين';
}
