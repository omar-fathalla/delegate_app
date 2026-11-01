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
}
