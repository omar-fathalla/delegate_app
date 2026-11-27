// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tashil';

  @override
  String get delegateApp => 'Employees App';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Log out';

  @override
  String get loginToContinue => 'Welcome back, please enter your details';

  @override
  String get loginSuccessful => 'Login Successful!';

  @override
  String get loginButton => 'Login';

  @override
  String get mobileNumber => 'Phone Number';

  @override
  String get password => 'Password';

  @override
  String get motherName => 'Mother\'s Name';

  @override
  String get enterMobileNumber => 'Please enter mobile number';

  @override
  String get enterPassword => 'Please enter password';

  @override
  String get nationalIdNumber => 'National ID number';

  @override
  String get enterNationalId => 'Please enter the national ID number';

  @override
  String get invalidNationalId => 'National ID must be 14 digits';

  @override
  String get invalidMobileNumber => 'Enter a valid mobile number';

  @override
  String get loginNationalIdHelp =>
      'Delegates sign in with their national ID. Other roles use their password.';

  @override
  String get invalidLoginCredentials =>
      'The phone number, national ID, or password is incorrect.';

  @override
  String get delegateAccountInactive =>
      'This account is pending or suspended. Please contact Tashil management.';

  @override
  String get tooManyLoginAttempts =>
      'Too many attempts. Please try again later.';

  @override
  String get loginTemporarilyUnavailable =>
      'Sign-in is temporarily unavailable. Please try again.';

  @override
  String get rememberMe => 'Remember Me';

  @override
  String get home => 'Home';

  @override
  String get profile => 'Profile';

  @override
  String get attendance => 'Attendance';

  @override
  String get myProfile => 'My Profile';

  @override
  String get personalInformation => 'Personal Information';

  @override
  String get delegateId => 'Delegate ID';

  @override
  String get delegateRole => 'Delegate';

  @override
  String get checkIn => 'Check In';

  @override
  String get checkOut => 'Check Out';

  @override
  String get checkedInSuccessfully => 'Checked In Successfully';

  @override
  String get checkedOutSuccessfully => 'Checked Out Successfully';

  @override
  String get scanToCheckIn => 'Scan to Check In';

  @override
  String get scanToCheckOut => 'Scan to Check Out';

  @override
  String get scanQrInstruction => 'Scan the QR code in the marketing office.';

  @override
  String scanForAction(String action) {
    return 'Scan to $action';
  }

  @override
  String pointCameraToQR(String action) {
    return 'Point camera at QR Code for $action';
  }

  @override
  String checkingInAt(String branch) {
    return 'Checking in at $branch...';
  }

  @override
  String get invalidQRCode =>
      'Invalid QR Code. Please scan a valid branch code.';

  @override
  String get currentStatus => 'Current Status';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get active => 'Active';

  @override
  String inLabel(String time) {
    return 'In: $time';
  }

  @override
  String outLabel(String time) {
    return 'Out: $time';
  }

  @override
  String noRecordsForMonth(String month) {
    return 'No attendance records for $month';
  }

  @override
  String get recentHistory => 'Recent History';

  @override
  String get noHistoryAvailable => 'No attendance records';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get unspecifiedBranch => 'Unspecified';

  @override
  String helloUser(String name) {
    return 'Hello, $name';
  }

  @override
  String historyInOut(String inTime, String outTime) {
    return 'In: $inTime - Out: $outTime';
  }

  @override
  String get errorGeneral => 'An error occurred. Please try again.';

  @override
  String get errorNetwork => 'No internet connection.';

  @override
  String get errorLocation => 'Could not determine your location.';

  @override
  String get errorOutOfRange => 'You are outside the worksite range.';

  @override
  String get errorMockLocation => 'Mock location detected. Cannot check in.';

  @override
  String get errorAuth => 'Invalid credentials.';

  @override
  String get success => 'Operation completed successfully';

  @override
  String get loading => 'Loading...';

  @override
  String get pendingSync => 'Pending sync';

  @override
  String get settings => 'Settings';

  @override
  String get companies => 'Companies';

  @override
  String get search => 'Search';

  @override
  String get language => 'Language';

  @override
  String get changeLanguage => 'Change Language';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String languageChangedTo(String language) {
    return 'Language changed to $language';
  }

  @override
  String duration(String hours, String minutes) {
    return 'Duration: ${hours}h ${minutes}m';
  }

  @override
  String get inProgress => 'In progress...';

  @override
  String get missingCheckOut => 'Check-out not recorded';

  @override
  String get fullName => 'Full Name';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get birthDate => 'Date of Birth';

  @override
  String get cityLabel => 'City';

  @override
  String get organizationAndCompany => 'Organization & Company';

  @override
  String get organizationLabel => 'Organization';

  @override
  String get companyLabel => 'Company';

  @override
  String get positionLabel => 'Position';

  @override
  String get documents => 'Documents';

  @override
  String get requestHistory => 'Request History';

  @override
  String get personalPhoto => 'Personal Photo';

  @override
  String get nationalId => 'National ID';

  @override
  String get authorizationLetter => 'Authorization Letter';

  @override
  String get insuranceLetter => 'Insurance Letter';

  @override
  String get healthCertificate => 'Health Certificate';

  @override
  String get paymentReceipt => 'Payment Receipt';

  @override
  String get electronicPaymentReceipt => 'Electronic Payment Receipt';

  @override
  String get pendingStatus => 'Pending';

  @override
  String uploadedOn(String date) {
    return 'Uploaded: $date';
  }

  @override
  String get clickToView => 'Click to View';

  @override
  String receiptCode(String code) {
    return 'Receipt Code: $code';
  }

  @override
  String get noRequestsYet => 'No requests yet';

  @override
  String get approvedStatus => 'Approved';

  @override
  String get rejectedStatus => 'Rejected';

  @override
  String get noDocumentsUploaded => 'No documents uploaded';

  @override
  String get retry => 'Retry';

  @override
  String get gender => 'Gender';

  @override
  String get male => 'Male';

  @override
  String get female => 'Female';

  @override
  String get joinDate => 'Join Date';

  @override
  String get employmentDetails => 'Employment Details';

  @override
  String get statusReason => 'Status Reason';

  @override
  String get profileComplete => 'Profile Complete';

  @override
  String get profileIncomplete => 'Profile Incomplete';

  @override
  String reviewedBy(String name) {
    return 'Reviewed By: $name';
  }

  @override
  String get notProvidedStatus => 'Not Provided';

  @override
  String get adminDashboard => 'Admin Dashboard';

  @override
  String get addBranch => 'Add New Branch';

  @override
  String get branchName => 'Branch Name';

  @override
  String get branchLocation => 'Branch Location';

  @override
  String get geofenceRadius => 'Attendance Radius (Meters)';

  @override
  String get saveBranch => 'Save Branch';

  @override
  String get branchAddedSuccessfully => 'Branch Added Successfully';

  @override
  String get pleaseEnterBranchName => 'Please enter branch name';

  @override
  String get pleaseSelectLocation => 'Please select a location on the map';

  @override
  String get searchCityOrRegion => 'Search city or region...';

  @override
  String get branches => 'Branches';

  @override
  String get roleBranchMarketing => 'Branch Marketing';

  @override
  String get roleBranchesMarketingManager => 'Branches Marketing Manager';

  @override
  String get roleBranchesMarketingMgrShort => 'Branches Marketing Mgr';

  @override
  String get roleMarketingPromotion => 'Marketing Promotion';

  @override
  String get branchMarketingFollowUp => 'Branch Marketing Follow-up';

  @override
  String get branchMarketingCoordination => 'Branch Marketing Coordination';

  @override
  String get admin => 'Admin';

  @override
  String get myLocation => 'My Location';

  @override
  String get locationServicesDisabled => 'Location services are disabled.';

  @override
  String get locationPermissionDenied => 'Location access denied';

  @override
  String get errorFetchingLocation => 'Error fetching location.';

  @override
  String get branchDetails => 'Branch Details';

  @override
  String get downloadQR => 'Download QR';

  @override
  String get qrSavedToGallery => 'QR Code saved to gallery successfully!';

  @override
  String get editName => 'Edit Name';

  @override
  String get editBranch => 'Edit Branch';

  @override
  String get branchUpdatedSuccessfully => 'Branch updated successfully.';

  @override
  String get deleteBranch => 'Delete Branch';

  @override
  String get deleteBranchConfirmation =>
      'Are you sure you want to delete this branch?';

  @override
  String get branchDeletedSuccessfully => 'Branch deleted successfully.';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get networkStatusOffline => 'Offline';

  @override
  String get networkStatusOnline => 'Online';

  @override
  String get noAccountContact =>
      'Don\'t have an account? Contact the following number';

  @override
  String get noAccountTitle => 'Don\'t have an account?';

  @override
  String get noAccountSubtitle => 'Contact the following number';

  @override
  String get contactNumber => '01211857725';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get helpCenter => 'Help center';

  @override
  String version(String version) {
    return 'Tashil Representative - Version $version';
  }

  @override
  String webVersion(String version) {
    return 'Version $version';
  }

  @override
  String get account => 'Account';

  @override
  String get privacyPolicyDesc =>
      'This Privacy Policy describes how we collect, use, and disclose your personal information when you use our delegate services. We are committed to protecting your privacy and ensuring your data is handled securely.';

  @override
  String get locationData => 'LOCATION DATA';

  @override
  String get locationDataDesc =>
      'Our app collects location data to enable real-time tracking of deliveries and to match delegates with nearby orders even when the app is closed or not in use. This data is essential for the core functionality of our service.';

  @override
  String get cameraAccess => 'CAMERA ACCESS';

  @override
  String get cameraAccessDesc =>
      'We require camera access to allow you to take photos of bills, packages, or delivery proofs. Photos are only captured when you explicitly use the camera feature within the app.';

  @override
  String get dataSecurity => 'DATA SECURITY';

  @override
  String get dataSecurityDesc =>
      'We implement industry-standard security measures to protect your data. We do not sell your personal data. Your information is shared only with authorized partners for service processing.';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get website => 'Website';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get egyptOffice => 'Egypt Office';

  @override
  String get uaeOffice => 'UAE Office';

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
  String get createAdmin => 'Create Admin';

  @override
  String get adminName => 'Admin Name';

  @override
  String get adminPhone => 'Phone Number';

  @override
  String get adminEmail => 'Email Address';

  @override
  String get pleaseEnterAdminName => 'Please enter admin name';

  @override
  String get pleaseEnterAdminPhone => 'Please enter phone number';

  @override
  String get pleaseEnterAdminEmail => 'Please enter email address';

  @override
  String get invalidPhoneNumber => 'Invalid phone number';

  @override
  String get invalidEmail => 'Invalid email address';

  @override
  String get adminCreatedSuccessfully =>
      'Admin account created successfully! Activation email sent.';

  @override
  String get manageAdmins => 'Manage Admins';

  @override
  String get noAdminsFound => 'No admins found';

  @override
  String get suspended => 'Suspended';

  @override
  String get editAdmin => 'Edit';

  @override
  String get deleteAdmin => 'Delete';

  @override
  String get suspendAdmin => 'Suspend';

  @override
  String get activateAdmin => 'Activate';

  @override
  String get deleteAdminConfirmation =>
      'Are you sure you want to delete this admin? This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get companyDelegates => 'Delegates';

  @override
  String get viewAttendance => 'View Attendance';

  @override
  String get noDelegatesFound => 'No delegates found';

  @override
  String get viewProfileData => 'View Profile';

  @override
  String get addDelegate => 'Add Delegate';

  @override
  String get addDelegateViaWeb => 'Add via Web';

  @override
  String get tasks => 'Tasks';

  @override
  String get todayOverview => 'Today\'s Overview';

  @override
  String get totalDelegates => 'Total Delegates';

  @override
  String get checkedInToday => 'Checked In Today';

  @override
  String get absentToday => 'Absent Today';

  @override
  String get addTask => 'Add Task';

  @override
  String get taskTitle => 'Task Title';

  @override
  String get taskDescription => 'Task Description';

  @override
  String get taskPriority => 'Priority';

  @override
  String get high => 'High';

  @override
  String get medium => 'Medium';

  @override
  String get low => 'Low';

  @override
  String get taskDueDate => 'Due Date';

  @override
  String get assignTo => 'Assign To';

  @override
  String get allDelegates => 'All Delegates';

  @override
  String get createTask => 'Create Task';

  @override
  String get taskCreatedSuccessfully => 'Task created successfully';

  @override
  String get taskUpdatedSuccessfully => 'Task updated successfully';

  @override
  String get noTasksFound => 'No tasks found';

  @override
  String get taskStatus => 'Task Status';

  @override
  String get taskPending => 'Pending';

  @override
  String get taskInProgress => 'In progress';

  @override
  String get taskCompleted => 'Completed';

  @override
  String get all => 'All';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get taskCancelled => 'Cancelled';

  @override
  String get taskDetails => 'Task Details';

  @override
  String get taskSchedule => 'Schedule';

  @override
  String get selectDelegate => 'Select Delegate';

  @override
  String get errorFieldRequired => 'This field is required';

  @override
  String get addTaskToGetStarted => 'Add a task to get started';

  @override
  String get myTasks => 'My Tasks';

  @override
  String get noTasksYet => 'No tasks yet';

  @override
  String get complete => 'Complete';

  @override
  String get delete => 'Delete';

  @override
  String get deleteTask => 'Delete Task';

  @override
  String get deleteTaskConfirmation =>
      'Are you sure you want to delete this task? This action cannot be undone.';

  @override
  String get notesHint => 'Add notes here...';

  @override
  String get notes => 'Notes';

  @override
  String get tasksSummary => 'Tasks Summary';

  @override
  String get total => 'Total';

  @override
  String get searchDelegates => 'Search delegates...';

  @override
  String get filterByStatus => 'Filter by status';

  @override
  String get noDelegateSearchResults => 'No delegates match your search';

  @override
  String get notifications => 'Notifications';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get newNotification => 'New notification';

  @override
  String get searchCompanies => 'Search Companies';

  @override
  String get searchCompaniesHint => 'Search for companies using company code';

  @override
  String get enterCompanyCode => 'Enter company code';

  @override
  String get clear => 'Clear';

  @override
  String get noCompaniesFound => 'No companies found';

  @override
  String get searchQuery => 'Search Query';

  @override
  String get errorOccurred => 'Error Occurred';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get manageMarketing => 'Manage Marketing Employees';

  @override
  String get noMarketingEmployeesFound => 'No marketing employees found';

  @override
  String get searchByPhone => 'Search by phone number...';

  @override
  String get filterByOrganization => 'Filter by organization';

  @override
  String get allOrganizations => 'All Organizations';

  @override
  String get marketingEmployee => 'Marketing Employee';

  @override
  String get editMarketingEmployee => 'Edit Employee';

  @override
  String get deleteMarketingEmployee => 'Delete Employee';

  @override
  String get deleteMarketingEmployeeConfirmation =>
      'Are you sure you want to delete this employee? This action cannot be undone.';

  @override
  String get suspendMarketingEmployee => 'Suspend Employee';

  @override
  String get activateMarketingEmployee => 'Activate Employee';

  @override
  String get employeeSuspended => 'Employee suspended';

  @override
  String get employeeActivated => 'Employee activated';

  @override
  String get employeeDeleted => 'Employee deleted successfully';

  @override
  String get employeeUpdated => 'Employee updated successfully';

  @override
  String get employeeName => 'Employee Name';

  @override
  String get employeePhone => 'Phone Number';

  @override
  String get employeeEmail => 'Email Address';

  @override
  String get organization => 'Organization';

  @override
  String get forgotCheckoutTitle => 'Pending Check-in Alert';

  @override
  String forgotCheckoutMessage(String oldBranch, String newBranch) {
    return 'You have a pending check-in at $oldBranch. Do you want to check out from it and check in to $newBranch?';
  }

  @override
  String previousDayCheckoutMessage(String oldBranch, String newBranch) {
    return 'You have a pending check-in from a previous day at $oldBranch. The system will check you out from it and check you in today at $newBranch.';
  }

  @override
  String get confirmAction => 'Confirm';

  @override
  String get photoPermissions => 'Photo';

  @override
  String get photoPermissionsDesc =>
      'Manage photo permissions and view photo reports';

  @override
  String get supervisor => 'Supervisor';

  @override
  String supervisorUser(String name) {
    return 'Supervisor: $name';
  }

  @override
  String adminUser(String name) {
    return 'Admin: $name';
  }

  @override
  String get paymentReceiptsReport => 'Payment Receipts Billing Report';

  @override
  String get uploadsCount => 'Uploads Count';

  @override
  String get totalUploadedReceipts => 'Total Uploaded Receipts';

  @override
  String get companiesWithUploads => 'Billed Companies';

  @override
  String get receiptsReport => 'Receipts Report';

  @override
  String get accountant => 'Financial Accountant';

  @override
  String get accountantDashboard => 'Financial Management Dashboard';

  @override
  String get financialReports => 'Financial Reports';

  @override
  String get paymentReceipts => 'Payment Receipts';

  @override
  String get subscriptionRequests => 'Subscription Requests';

  @override
  String get walletsManagement => 'Wallets Management';

  @override
  String get violationsPolicy => 'Violations policy';

  @override
  String get myViolations => 'My violations';

  @override
  String get switchOrganization => 'Switch organization';

  @override
  String get manageOrganizationsChains => 'Manage organizations and chains';

  @override
  String get delegateSubscriptionsMenu => 'Delegate subscriptions';

  @override
  String get mainMenu => 'Main menu';

  @override
  String get navRequests => 'Requests';

  @override
  String get navPhotoReports => 'Photos';

  @override
  String get roleDelegate => 'Delegate';

  @override
  String get roleSupervisor => 'Supervisor';

  @override
  String get roleCompanyAdmin => 'Company admin';

  @override
  String get roleSuperAdmin => 'Super admin';

  @override
  String get roleOrgAdmin => 'Organization admin';

  @override
  String get roleTechSupport => 'Technical support';

  @override
  String get roleMarketing => 'Marketing';

  @override
  String get roleHr => 'HR';

  @override
  String get defaultUserName => 'User';

  @override
  String get offlineBannerTitle => 'You\'re offline';

  @override
  String offlineLastSync(Object time) {
    return 'Last updated $time';
  }

  @override
  String get offlineNoSyncYet => 'We\'ll update when you\'re back online';

  @override
  String get offlineNotifications =>
      'Notifications can\'t load while you\'re offline. Connect and try again.';

  @override
  String get refreshFailed =>
      'Couldn\'t refresh. Check your connection and try again.';

  @override
  String get startPhotosCta => 'Start photos';

  @override
  String get switchOn => 'On';

  @override
  String get switchOff => 'Off';

  @override
  String releaseVersionDate(Object version, Object date) {
    return 'Version $version – $date';
  }

  @override
  String get feedbackTypeFeature => 'Feature request';

  @override
  String get feedbackTypeBug => 'Report a problem';

  @override
  String get feedbackTypeQuestion => 'General question';

  @override
  String get feedbackTypeImprovement => 'Improvement';

  @override
  String get feedbackTypeOther => 'Other';

  @override
  String get reqTitle => 'My requests';

  @override
  String get refreshAction => 'Refresh';

  @override
  String get newRequest => 'New request';

  @override
  String get reqEmptyAll => 'No requests yet';

  @override
  String get reqEmptyFilter => 'No requests with this status';

  @override
  String get reqEmptyHint => 'Tap “New request” to send one to your supervisor';

  @override
  String get annualLeaveBalance => 'Annual leave balance';

  @override
  String get weeklyOffPlan => 'Weekly day-off plan';

  @override
  String get daysOffPerMonth => '4 days off/month';

  @override
  String get weeklyDayOff => 'Weekly day off';

  @override
  String get oneDayEvery7 => '1 day every 7 days';

  @override
  String get hourlyPermission => 'Hourly permission';

  @override
  String get availableLabel => 'Available';

  @override
  String get annualBalance21 => 'Annual: 21 days';

  @override
  String get onceActivated => 'Once activated';

  @override
  String get filterAll => 'All';

  @override
  String get statusPendingReview => 'Pending';

  @override
  String get statusApprovedPl => 'Approved';

  @override
  String get statusRejectedPl => 'Rejected';

  @override
  String get leaveSick => 'Sick leave';

  @override
  String get leaveEmergency => 'Emergency leave';

  @override
  String get excuseLate => 'Late arrival';

  @override
  String get excuseEarlyLeave => 'Early leave';

  @override
  String get excuseAbsence => 'Excused absence';

  @override
  String get leaveUnpaid => 'Unpaid leave';

  @override
  String get leaveAnnual => 'Annual leave';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusPending => 'Pending';

  @override
  String get previewAttachment => 'Preview attachment';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String get cancelRequestConfirm => 'Cancel this request?';

  @override
  String get keepRequest => 'Keep';

  @override
  String get yesCancel => 'Yes, cancel';

  @override
  String get requestCancelled => 'Request cancelled';

  @override
  String get requestType => 'Request type';

  @override
  String get weeklyPlanAvailableInfo =>
      'You can request: hourly permission, an excused absence, or unpaid leave.';

  @override
  String remainingDays(int count) {
    return 'Remaining: $count days';
  }

  @override
  String usedDays(int count) {
    return 'Used: $count days';
  }

  @override
  String totalQuotaDays(int count) {
    return 'Total: $count days';
  }

  @override
  String forYear(int year) {
    return 'For $year';
  }

  @override
  String reasonLabel(Object reason) {
    return 'Reason: $reason';
  }

  @override
  String rejectReasonLabel(Object reason) {
    return 'Rejection reason: $reason';
  }

  @override
  String approvedBy(Object name) {
    return 'Approved by $name';
  }

  @override
  String get homeSupervisorsTitle => 'Your supervisors';

  @override
  String homeGreeting(Object firstName) {
    return 'Hi, $firstName';
  }

  @override
  String get roleFieldSupervisor => 'Field supervisor';

  @override
  String get homeCoreDuties => 'Your core duties';

  @override
  String get homeDutyAttendance => 'Check in and out from the branch location';

  @override
  String get homeDutyTasks => 'Complete and track your daily tasks';

  @override
  String get homeDutyPhotos =>
      'Photograph offers and brands in hypermarkets and branches';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get companySupervisor => 'Company supervisor';

  @override
  String supervisorOfCompany(Object companyName) {
    return 'Supervisor · $companyName';
  }

  @override
  String get assignedCompanySupervisor => 'Assigned company supervisor';

  @override
  String get callAction => 'Call';

  @override
  String get offerPhotosTitle => 'Offer photos';

  @override
  String get offerPhotosSubtitle => 'Photograph offers inside the hypermarket';

  @override
  String homeAttendanceSummary(Object monthName) {
    return 'Attendance – $monthName';
  }

  @override
  String get detailsAction => 'Details';

  @override
  String get statAttended => 'Attended';

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get statAbsent => 'Absent';

  @override
  String get statDaysOff => 'Days off';

  @override
  String leavesOfFour(int count) {
    return '$count of 4 days';
  }

  @override
  String get workPolicyNote =>
      '26 workdays/month • 4 days off not counted as absence';

  @override
  String get chainGomlaMarket => 'Gomla Market';

  @override
  String get chainFathallaMarket => 'Fathalla Market';

  @override
  String get chainZahranMarket => 'Zahran Market';

  @override
  String get recentBranchActivity => 'Recent activity';

  @override
  String get viewLog => 'View history';

  @override
  String get unknownBranch => 'Unknown branch';

  @override
  String get onShift => 'On shift';

  @override
  String durationHm(Object hours, Object minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String branchLabel(Object cleanBranchName) {
    return 'Branch: $cleanBranchName';
  }

  @override
  String get homeRequestsSubtitle =>
      'Submit and track leave and excuse requests';

  @override
  String companySupervisorWithName(Object companyName) {
    return 'Company supervisor ($companyName)';
  }

  @override
  String errorWithMessage(Object error) {
    return 'Error: $error';
  }

  @override
  String get noSupervisorForCompany =>
      'No supervisor registered for this company yet';

  @override
  String pendingCountBadge(Object count) {
    return '$count pending';
  }

  @override
  String get orgMarketing => 'Marketing';

  @override
  String get orgAdminPanel => 'Administration';

  @override
  String get orgAccounting => 'Finance & accounting';

  @override
  String switchedToOrg(Object orgLabel) {
    return 'Switched to $orgLabel';
  }

  @override
  String get unknownOrganization => 'Unknown organization';

  @override
  String get alreadyInOrg => 'You\'re already in this organization.';

  @override
  String get logoutConfirm => 'Log out?\nYour local data will be saved first.';

  @override
  String get logoutDialogTitle => 'Log out?';

  @override
  String get logoutDialogBody => 'Your local data is saved first';

  @override
  String logoutFailed(Object error) {
    return 'Couldn\'t log out: $error';
  }

  @override
  String get backAction => 'Back';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get rateTheApp => 'Rate the app';

  @override
  String get manageFeedback => 'Manage feedback';

  @override
  String get myFeedback => 'My feedback';

  @override
  String get photoPermissions2 => 'Photo permissions';

  @override
  String get appColor => 'App color';

  @override
  String get attCheckingZone => 'Checking location…';

  @override
  String get attVerifyingCoords => 'Checking your location…';

  @override
  String get attInsideZone => 'You\'re in the work zone';

  @override
  String attWithinBranchRange(Object branch) {
    return 'Within range of $branch';
  }

  @override
  String get attOutsideZone => 'You\'re outside the work zone';

  @override
  String attMoveCloserTo(Object branch) {
    return 'Move closer to $branch to check in';
  }

  @override
  String get attOutsideApprovedBranches => 'You\'re not at an approved branch';

  @override
  String distanceKmM(Object km, Object meters) {
    return '$km km ($meters m)';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get currentMonth => 'Current month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get attWorkPolicyNote =>
      '26 workdays • 4 days off not counted as absence';

  @override
  String distanceLabel(Object formattedDistance) {
    return 'Distance: $formattedDistance';
  }

  @override
  String radiusLabel(Object allowedRadius) {
    return 'Allowed radius: $allowedRadius m';
  }

  @override
  String get recheckLocation => 'Check again';

  @override
  String get activeChain => 'Current chain';

  @override
  String get attChainLabel => 'Chain';

  @override
  String get attBranchLabel => 'Branch';

  @override
  String get attAllBranches => 'All branches';

  @override
  String get attMonthProgressTitle => 'Days attended of work days';

  @override
  String attMonthProgress(int count, int total) {
    return 'Attended $count of $total work days';
  }

  @override
  String get attDurationLabel => 'Duration';

  @override
  String get attCheckInLabel => 'Check-in';

  @override
  String get attCheckOutLabel => 'Check-out';

  @override
  String get notifKindAttention => 'Needs attention';

  @override
  String get notifKindDone => 'Done';

  @override
  String get notifKindChange => 'Change';

  @override
  String get notifKindWork => 'To do';

  @override
  String get notifKindAttendance => 'Attendance';

  @override
  String get notifKindInfo => 'Info';

  @override
  String get reqRejectReasonTitle => 'Reason for rejection';

  @override
  String get reqDecidedBy => 'Decided by';

  @override
  String reqHoursWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours',
      one: 'hour',
    );
    return '$_temp0';
  }

  @override
  String reqDaysWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String get reqDurationLabel => 'Duration';

  @override
  String get reqFilterPending => 'Pending';

  @override
  String get photosCaptureAction => 'Photograph a display';

  @override
  String get photoLoadFailed => 'Couldn\'t load the photo';

  @override
  String get photoPendingBanner =>
      'This photo is still on the phone. It uploads when you are back online.';

  @override
  String get photoBannerOk => 'OK';

  @override
  String get photoShare => 'Share';

  @override
  String get photoShareFailed => 'Couldn\'t share the photo';

  @override
  String get photoOpenMap => 'Open on the map';

  @override
  String get photoMapFailed => 'Couldn\'t open the map';

  @override
  String get photoPrevious => 'Previous photo';

  @override
  String get photoNext => 'Next photo';

  @override
  String photoCounter(int index, int total) {
    return '$index of $total';
  }

  @override
  String photoSemantic(String branch, String time) {
    return 'Photo at $branch, $time';
  }

  @override
  String get profileWorkInfo => 'Work details';

  @override
  String get profileDelegateCode => 'Delegate code';

  @override
  String get profileChains => 'Chains';

  @override
  String get profileCopy => 'Copy';

  @override
  String get profileCopied => 'Code copied';

  @override
  String get profileShowId => 'Show number';

  @override
  String get profileHideId => 'Hide number';

  @override
  String get taskStart => 'Start task';

  @override
  String get taskFinish => 'Mark as done';

  @override
  String get taskOverdueLabel => 'Overdue';

  @override
  String taskOverdueBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This task is $count days overdue',
      one: 'This task is 1 day overdue',
    );
    return '$_temp0';
  }

  @override
  String taskDueInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count days',
      one: 'Tomorrow',
    );
    return '$_temp0';
  }

  @override
  String get taskProofSection => 'Proof of work';

  @override
  String get taskFrom => 'From';

  @override
  String get taskAssignedToLabel => 'For';

  @override
  String get taskAssignedAll => 'All delegates';

  @override
  String get taskSentAt => 'Sent';

  @override
  String get taskDoneAt => 'Done';

  @override
  String get taskSharedForYouOnly =>
      'A task for everyone: marking it done marks it for you only';

  @override
  String get taskProofRequiredMessage =>
      'Photo needed: this task needs a photo proving you did it';

  @override
  String get taskProofRequiredOption => 'Require a proof photo before «Done»';

  @override
  String taskCompletedByCount(int count) {
    return 'Done by: $count';
  }

  @override
  String get tasksFilterOpen => 'Open';

  @override
  String get tasksFilterDone => 'Done';

  @override
  String get tasksGroupOverdue => 'Overdue';

  @override
  String get tasksGroupOpen => 'Coming up';

  @override
  String get tasksGroupDone => 'Finished';

  @override
  String taskLateBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days late',
      one: '1 day late',
    );
    return '$_temp0';
  }

  @override
  String get captureStepPlace => 'Place';

  @override
  String get captureStepPhotos => 'Photos';

  @override
  String capturePermissionUntil(String date) {
    return 'Permission valid until $date';
  }

  @override
  String get captureTapToReview =>
      'Tap a photo to view it large, retake or remove it.';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAuto => 'Auto';

  @override
  String get settingsContrast => 'Contrast';

  @override
  String get settingsContrastHint =>
      'For text and borders. «High» reads better in sunlight.';

  @override
  String get settingsContrastStandard => 'Standard';

  @override
  String get settingsContrastMedium => 'Medium';

  @override
  String get settingsContrastHigh => 'High';

  @override
  String get settingsColorHint =>
      'Every app colour is generated from this one.';

  @override
  String get settingsAbout => 'About';

  @override
  String get feedbackOpen => 'Open';

  @override
  String get feedbackAnswered => 'Answered';

  @override
  String get feedbackSentAt => 'Sent';

  @override
  String get feedbackHasAnswer => 'Answered';

  @override
  String get feedbackNoAnswer => 'Not yet';

  @override
  String get feedbackYourMessage => 'Your message';

  @override
  String get feedbackScreenshot => 'Attached screenshot';

  @override
  String get feedbackNoAnswerYet =>
      'No answer yet. You will get a notification when the team replies.';

  @override
  String get allChains => 'All chains';

  @override
  String attNoSessionsInChain(Object chain) {
    return 'No attendance records for $chain this month';
  }

  @override
  String attDaysInOtherChains(Object count) {
    return 'You have $count attended days in other chains.';
  }

  @override
  String get attAutoClosedNote =>
      'Checked out automatically 11.5 hours after the shift started, since no check-out was recorded';

  @override
  String get autoClosedAuto => 'Auto-closed (11.5h)';

  @override
  String get checkOut2 => 'Check out';

  @override
  String get attCheckingLocation => 'Checking location…';

  @override
  String get checkIn2 => 'Check in';

  @override
  String get noBranchesForOrg => 'No branches for this organization yet';

  @override
  String attYouAreWithinBranch(Object branch) {
    return 'You are within range of $branch';
  }

  @override
  String get attMoveCloser => 'Move closer to the branch to check in';

  @override
  String get attCheckInSavedOffline =>
      'Check-in saved on this device. It will sync when you are back online.';

  @override
  String get attCheckOutSavedOffline =>
      'Check-out saved on this device. It will sync when you are back online.';

  @override
  String get syncDone => 'Synced';

  @override
  String get syncFailed => 'Couldn\'t sync';

  @override
  String attDelegateOfCompany(Object companyName) {
    return 'Delegate · $companyName';
  }

  @override
  String get attendanceLog => 'Attendance history';

  @override
  String distanceMeters(Object meters) {
    return '$meters m';
  }

  @override
  String get attLocatingYou => 'Finding your location and checking branches…';

  @override
  String get attLocatingShort => 'Finding your location…';

  @override
  String get attEarlyCheckOutTitle => 'Check out already?';

  @override
  String attEarlyCheckOutBody(int minutes) {
    return 'You checked in $minutes min ago. Checking out now will close this attendance.';
  }

  @override
  String get attEarlyCheckOutConfirm => 'Yes, check out';

  @override
  String get attEarlyCheckOutCancel => 'Stay checked in';

  @override
  String get attLocationUnavailable =>
      'Couldn\'t get your location. Turn on GPS.';

  @override
  String attInsideBranchWithDistance(Object branch, Object meters) {
    return 'You are within range of $branch ($meters m)';
  }

  @override
  String attOutsideBranchWithRadius(Object meters, Object radius) {
    return 'You are outside the branch range ($meters m). Allowed range: $radius m.';
  }

  @override
  String get attEnsureGps => 'Make sure GPS is on and wait for your location.';

  @override
  String attCannotActOutside(Object action, Object distance) {
    return 'You can\'t $action while outside the branch ($distance). Please be inside the branch.';
  }

  @override
  String attCannotActOutsideNoDistance(Object action) {
    return 'You can\'t $action while outside the branch. Please be inside the branch.';
  }

  @override
  String attCannotActOutsideAtBranch(
    Object action,
    Object branch,
    Object distance,
  ) {
    return 'You can\'t $action while outside $branch ($distance). Please be inside the branch.';
  }

  @override
  String attCannotActOutsideBranchOnly(Object action, Object branch) {
    return 'You can\'t $action while outside $branch. Please be inside the branch.';
  }

  @override
  String attCheckingInAt(Object branchName) {
    return 'Checking in at $branchName…';
  }

  @override
  String get locationServicesOff => 'Location services are off. Turn them on.';

  @override
  String get locationPermissionDenied2 => 'Location permission denied';

  @override
  String get locationPermissionDeniedForever =>
      'Location access is off. Turn it on in Settings.';

  @override
  String get fakeGpsDetected =>
      'A fake GPS app was detected. Turn it off to check in or out.';

  @override
  String get locationTimeout =>
      'We couldn\'t get your location. Stand in an open area, open Google Maps until the blue dot settles, turn on Google Location Accuracy, then try again.';

  @override
  String get locationError => 'Couldn\'t get your location. Try again.';

  @override
  String get trustedTime => 'Trusted time';

  @override
  String get attActionCheckIn => 'check in';

  @override
  String get attActionCheckOut => 'check out';

  @override
  String get userNotFound => 'User not found';

  @override
  String get accountNotIdentified => 'Couldn\'t identify the account';

  @override
  String get profilePhotoUpdated => 'Profile photo updated';

  @override
  String photoUploadFailed(Object error) {
    return 'Couldn\'t upload the photo: $error';
  }

  @override
  String get profilePhotoDeleted => 'Profile photo deleted';

  @override
  String photoDeleteFailed(Object error) {
    return 'Couldn\'t remove the photo: $error';
  }

  @override
  String get profilePhoto => 'Profile photo';

  @override
  String get takePhotoCamera => 'Take a photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get removeCurrentPhoto => 'Delete photo';

  @override
  String get roleSuperAdmin2 => 'Super admin';

  @override
  String get roleTechSupport2 => 'Technical support';

  @override
  String get roleOrgAdmin2 => 'Organization admin';

  @override
  String get roleCompanyAdmin2 => 'Company admin';

  @override
  String get roleHrOfficer => 'HR officer';

  @override
  String get roleAccountant => 'Accounting';

  @override
  String get roleMarketing2 => 'Marketing';

  @override
  String get personalInfo => 'Personal information';

  @override
  String get nameLabel => 'Name';

  @override
  String get emailLabel => 'Email';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get securitySection => 'Security';

  @override
  String get changePassword => 'Change password';

  @override
  String editField(Object label) {
    return 'Edit $label';
  }

  @override
  String get nameUpdated => 'Name updated';

  @override
  String get emailUpdated => 'Email updated';

  @override
  String get phoneUpdated => 'Phone number updated';

  @override
  String get editName2 => 'Edit name';

  @override
  String get editEmail => 'Edit email';

  @override
  String get editPhone => 'Edit phone number';

  @override
  String get fullName2 => 'Full name';

  @override
  String get newEmail => 'New email';

  @override
  String get newPhone => 'New phone number';

  @override
  String get enterName => 'Enter your name';

  @override
  String get enterEmail => 'Enter your email';

  @override
  String get enterPhone => 'Enter your phone number';

  @override
  String get nameMin3 => 'Name must be at least 3 characters';

  @override
  String get invalidEmail2 => 'Enter a valid email';

  @override
  String get invalidPhone => 'Enter a valid phone number';

  @override
  String get saveAction => 'Save';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get currentPassword => 'Current password';

  @override
  String get enterCurrentPassword => 'Enter your current password';

  @override
  String get newPassword => 'New password';

  @override
  String get enterNewPassword => 'Enter a new password';

  @override
  String get passwordMin6 => 'Password must be at least 6 characters';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get enterConfirmPassword => 'Confirm your password';

  @override
  String get passwordsDontMatch => 'Passwords don\'t match';

  @override
  String get refreshPolicy => 'Refresh';

  @override
  String allPolicyItems(Object count) {
    return 'All items ($count)';
  }

  @override
  String get penPolicyCardBody =>
      'The deduction for each violation, first time and when repeated.';

  @override
  String get searchPolicy => 'Search the policy';

  @override
  String allWithCount(Object count) {
    return 'All ($count)';
  }

  @override
  String get adminRestricted => 'Admin only';

  @override
  String get firstTime => 'First time';

  @override
  String amountEgp(Object amount) {
    return '$amount EGP';
  }

  @override
  String get whenRepeated => 'When repeated';

  @override
  String get perManagementDecision => 'Per management decision';

  @override
  String plannedAction(Object action) {
    return 'Action: $action';
  }

  @override
  String get noResults => 'No results';

  @override
  String get tryOtherSearch => 'Try other words or a different category.';

  @override
  String get noViolationDocs => 'No attachments';

  @override
  String get violationReceipt => 'Violation document';

  @override
  String get closeAction => 'Close';

  @override
  String get imageLoadFailed => 'Couldn\'t load image';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get attachedDocuments => 'Attachments';

  @override
  String receiptNumber(Object number) {
    return 'Document $number';
  }

  @override
  String get photoReceipt => 'Document photo';

  @override
  String get tapToPreview => 'Tap to preview';

  @override
  String get tapToOpen => 'Tap to open';

  @override
  String get deleteAllNotifications => 'Delete all notifications';

  @override
  String get deleteAllNotificationsConfirm =>
      'Delete all notifications from your list?\n(They won\'t appear in your account again but stay in the system log.)';

  @override
  String get allNotificationsDeleted =>
      'All notifications deleted from your list';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get sendNewNotification => 'Send notification';

  @override
  String get deleteNotification => 'Delete notification';

  @override
  String get deleteNotificationConfirm =>
      'Delete this notification from your list?\n(It stays in the system log.)';

  @override
  String get notificationDeleted => 'Notification deleted';

  @override
  String get systemAdministration => 'System administration';

  @override
  String senderLine(Object name, Object role) {
    return 'From: $name ($role)';
  }

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get viewTask => 'View task';

  @override
  String get updateAppNow => 'Update now';

  @override
  String get justNow => 'Just now';

  @override
  String get taskCompletedConfirmed => 'Task marked as completed';

  @override
  String get taskStarted => 'Task started';

  @override
  String get noTasksNow => 'No tasks right now';

  @override
  String get tasksAppearHere =>
      'Tasks will appear here as soon as they are assigned to you.';

  @override
  String get taskDeleted => 'Task deleted';

  @override
  String taskDeleteFailed(Object error) {
    return 'Couldn\'t delete the task: $error';
  }

  @override
  String timeAgoDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String timeAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String timeAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String get confirmDeletePhoto => 'Delete photo?';

  @override
  String deletePhotoFromConfirm(Object delegateName, Object branch) {
    return 'Delete this photo sent by \"$delegateName\" at \"$branch\"?';
  }

  @override
  String get photoDeletePermanentNote =>
      'The photo will be permanently deleted from the database and storage.';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get chooseMonth => 'Choose month';

  @override
  String photosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
      zero: 'No photos',
    );
    return '$_temp0';
  }

  @override
  String get photoReportsTitle => 'Photo reports';

  @override
  String get refreshPhotos => 'Refresh photos';

  @override
  String get photosArchiveNote =>
      'Photos are stored in the company archive, separate from delegate accounts';

  @override
  String get totalPhotos => 'Total photos';

  @override
  String get branchesVisited => 'Branches visited';

  @override
  String get activeDelegates => 'Active delegates';

  @override
  String get byDate => 'By date';

  @override
  String get byBranch => 'By branch';

  @override
  String get byDelegate => 'By delegate';

  @override
  String get photoReportsLoadFailed => 'Couldn\'t load photo reports';

  @override
  String get unknownDelegate => 'Unknown delegate';

  @override
  String get pendingOnPhone => 'On phone';

  @override
  String get uploadedToServer => 'Uploaded';

  @override
  String noPhotosInMonth(Object month) {
    return 'No photos in $month';
  }

  @override
  String get useArrowsForMonths =>
      'Use the arrows above to view earlier months.';

  @override
  String get photoDetails => 'Photo details';

  @override
  String get deletePhotoPermanently => 'Delete photo permanently';

  @override
  String get pinchToZoom => 'Pinch to zoom in';

  @override
  String get deletePhoto => 'Delete photo';

  @override
  String get photoSavedToGallery => 'Photo saved to your gallery.';

  @override
  String get grantPhotosPermission =>
      'Allow photo access in your phone settings.';

  @override
  String photoSaveFailed(Object error) {
    return 'Couldn\'t save the photo: $error';
  }

  @override
  String get savingPhoto => 'Saving photo…';

  @override
  String get savedToPhone => 'Saved to phone';

  @override
  String get savePhoto => 'Save photo';

  @override
  String get branchField => 'Branch';

  @override
  String get capturedAtField => 'Captured at';

  @override
  String get delegateField => 'Delegate';

  @override
  String get delegateCommentField => 'Delegate\'s comment';

  @override
  String cameraOpenFailed(Object error) {
    return 'Couldn\'t open the camera: $error';
  }

  @override
  String get photoRemovedFromSession => 'Photo deleted';

  @override
  String get photoStampFailed =>
      'Couldn\'t add the date and branch to the photo. It will be uploaded without them.';

  @override
  String get offerPhotosSupervisor => 'Offer photos (supervisor)';

  @override
  String photosSavedOffline(Object count) {
    return '$count photos saved on this device. They will upload automatically when you are back online.';
  }

  @override
  String photosUploaded(Object count) {
    return '$count photos uploaded and the report saved.';
  }

  @override
  String get photoSavedOffline =>
      'Photo saved on this device. It will upload automatically when you are back online.';

  @override
  String get photoUploaded => 'Photo uploaded and the report saved.';

  @override
  String get loadingPhotoPermissions => 'Loading photo permissions…';

  @override
  String get choosePhotoPermission => 'Choose a photo permission *';

  @override
  String permissionOption(Object companyName, Object dept, Object length) {
    return '$companyName$dept - $length branches';
  }

  @override
  String branchWithId(Object id) {
    return 'Branch $id';
  }

  @override
  String offerPhotoPermissionOf(Object companyName) {
    return 'Photo permission: $companyName';
  }

  @override
  String companyLabel2(Object companyName) {
    return 'Company: $companyName';
  }

  @override
  String departmentLabel(Object department) {
    return 'Department: $department';
  }

  @override
  String noBranchesInPermissionFor(Object organizationName) {
    return 'No branches are registered for ($organizationName) in this permission.';
  }

  @override
  String get noBranchesInPermission =>
      'No branches are set for this permission yet. Ask your supervisor to add them.';

  @override
  String chooseBranchOf(Object organizationName) {
    return 'Select branch ($organizationName) *';
  }

  @override
  String get chooseBranchRequired => 'Select branch *';

  @override
  String get takeOfferPhotos => 'Take offer photos';

  @override
  String get multiPhotoHint =>
      'You can take several photos of this branch\'s products and stands at once';

  @override
  String get takeFirstPhoto => 'Take first photo';

  @override
  String get visitGallery => 'Visit photos';

  @override
  String get addPhoto => 'Add photo';

  @override
  String photoNumber(Object number) {
    return 'Photo $number';
  }

  @override
  String get retakePhoto => 'Retake';

  @override
  String get viewPhotoFullScreen => 'View full screen';

  @override
  String get addAction => 'Add';

  @override
  String visitNotesLabel(Object count) {
    return 'Visit notes ($count photos) (optional)';
  }

  @override
  String get visitNotesHint =>
      'e.g. Products displayed, shelf arranged and prices clearly visible…';

  @override
  String uploadingPhotoXofY(Object current, Object total) {
    return 'Uploading photo $current of $total…';
  }

  @override
  String get uploadingPhotosReport => 'Uploading photos and saving the report…';

  @override
  String nameCompanySupervisor(Object fullName) {
    return '$fullName (company supervisor)';
  }

  @override
  String get chooseBranchFirst => 'Choose a branch first.';

  @override
  String get takeAtLeastOnePhoto => 'Take at least one photo before saving.';

  @override
  String submitReportCount(Object count) {
    return 'Submit report ($count photos)';
  }

  @override
  String get chooseBranchToStart => 'Choose a branch to start taking photos';

  @override
  String get chooseBranchHint =>
      'Select the branch you are in from the list above to enable the camera button.';

  @override
  String get noPhotoPermissions => 'No photo permissions right now';

  @override
  String get askSupervisorForPermission =>
      'Ask your supervisor for a photo permission.';

  @override
  String photoReportsOf(Object companyName) {
    return 'Photo reports: $companyName';
  }

  @override
  String get loadingPhotoReports => 'Loading photo reports…';

  @override
  String get noUploadedPhotos => 'No uploaded photos yet';

  @override
  String get filterByBranch => 'Filter by branch';

  @override
  String get allBranches => 'All branches';

  @override
  String get filterByDelegate => 'Filter by delegate';

  @override
  String get allDelegates2 => 'All delegates';

  @override
  String shownResults(Object shown, Object total) {
    return 'Showing $shown of $total';
  }

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get noComment => 'No comment';

  @override
  String showMorePhotos(Object count) {
    return 'Show more ($count more photos)';
  }

  @override
  String get loadingPhotosReports => 'Loading photos and reports…';

  @override
  String syncingPhotosXofY(Object synced, Object total) {
    return 'Uploading photos ($synced of $total)…';
  }

  @override
  String get syncingRemainingPhotos => 'Uploading remaining photos…';

  @override
  String photosSavedOnPhone(Object count) {
    return '$count photos saved on the phone';
  }

  @override
  String get waitingToUpload => 'Will upload when you are online';

  @override
  String get syncNow => 'Sync now';

  @override
  String get noFeedbackYet => 'No feedback yet';

  @override
  String get sendFirstFeedback => 'Send your first feedback';

  @override
  String get adminResponse => 'Admin response';

  @override
  String get feedbackIntro => 'Your opinion matters. Help us improve the app';

  @override
  String get feedbackType => 'Type';

  @override
  String get yourMessage => 'Your message';

  @override
  String get feedbackHint => 'Write your feedback';

  @override
  String get enterMessage => 'Enter your message';

  @override
  String get messageTooShort => 'Message is too short (at least 10 characters)';

  @override
  String get screenshotOptional => 'Screenshot (optional)';

  @override
  String get chooseImage => 'Choose photo';

  @override
  String get sendRequestAction => 'Send request';

  @override
  String get sendAction => 'Send';

  @override
  String get thankYou => 'Thank you!';

  @override
  String get feedbackReceived =>
      'We\'ve received your feedback and will review it soon.';

  @override
  String get okAction => 'OK';

  @override
  String get loginSubtitleStaff => 'Choose your account type and sign in';

  @override
  String get loginSubtitleDelegate =>
      'Choose your account type and enter your details';

  @override
  String get staffLabel => 'Staff';

  @override
  String get forgotPasswordQ => 'Forgot password?';

  @override
  String get phoneHelper => 'The phone number registered with your company';

  @override
  String get nationalIdHelper => '14 digits';

  @override
  String get showAction => 'Show';

  @override
  String get hideAction => 'Hide';

  @override
  String get enterPassword2 => 'Enter your password';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get contactSupport => 'Contact support';

  @override
  String get checkHighlightedFields => 'Check the highlighted fields';

  @override
  String get resetLinkSentIfRegistered =>
      'If this email is registered, a reset link is on its way.';

  @override
  String get resetLinkFailed => 'Couldn\'t send the reset link. Try again.';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get sendLink => 'Send link';

  @override
  String get selectOrganization => 'Select organization';

  @override
  String get multipleOrgsChoose =>
      'You\'re registered in more than one organization. Choose one to continue.';

  @override
  String get weeklyPlanNote =>
      'You get one day off a week (4 a month). Annual leave becomes available once your supervisor approves it.';

  @override
  String dateWithHours(Object date, Object hours) {
    return '$date • (${hours}h)';
  }

  @override
  String hoursCount(Object count) {
    return '$count h';
  }

  @override
  String cancelRequestFailed(Object error) {
    return 'Couldn\'t cancel the request: $error';
  }

  @override
  String get requestAttachment => 'Attachment';

  @override
  String get attachmentLoadFailed => 'Couldn\'t load the attachment image';

  @override
  String get annualLeaveFromBalance => 'Annual leave (from annual balance)';

  @override
  String get annualLeaveUnavailable => 'Annual leave (not available yet)';

  @override
  String get lateArrivalHourly => 'Late arrival (hourly)';

  @override
  String get earlyLeaveHourly => 'Early leave (hourly)';

  @override
  String get excusedAbsenceFullDay => 'Excused absence (full day)';

  @override
  String get dateField => 'Date';

  @override
  String get timeField => 'Time';

  @override
  String get fromField => 'From';

  @override
  String get toField => 'To';

  @override
  String get periodField => 'Period';

  @override
  String daysExceedBalance(Object requested, Object remaining) {
    return 'Requested days ($requested) exceed your remaining balance ($remaining)';
  }

  @override
  String get reasonField => 'Reason';

  @override
  String get reasonHint => 'Briefly describe the reason';

  @override
  String get attachmentOptional => 'Attachment (optional)';

  @override
  String get cameraLabel => 'Camera';

  @override
  String get galleryLabel => 'Gallery';

  @override
  String get sendingRequest =>
      'Uploading the attachment and sending your request…';

  @override
  String get enterLeaveReason => 'Enter the reason for the leave or excuse';

  @override
  String get annualNotActive =>
      'Annual leave isn\'t active on your account yet. Choose another type.';

  @override
  String get requestSent =>
      'Your request was sent to your supervisor and is pending review.';

  @override
  String sendRequestFailed(Object error) {
    return 'Couldn\'t send the request: $error';
  }

  @override
  String get sendingEllipsis => 'Sending…';

  @override
  String durationLabel(Object duration) {
    return 'Duration: $duration';
  }

  @override
  String get settingsGeneral => 'General';

  @override
  String get senderRoleSystem => 'System';

  @override
  String get senderRoleCompanySupervisor => 'Company supervisor';

  @override
  String get senderRoleOrgAdmin => 'Organization admin';

  @override
  String get senderRoleBranchesMarketing => 'Branch marketing';

  @override
  String get senderRolePromotionMarketing => 'Promotion marketing';

  @override
  String get senderRoleMarketing => 'Marketing';

  @override
  String get senderRoleTechSupport => 'Tech support';

  @override
  String codeLabel(Object code) {
    return 'Code: $code';
  }

  @override
  String get policyOfficialSubtitle => 'Official list of violations and fines';

  @override
  String get catBranchRules => 'Branch rule violation';

  @override
  String get catTheftDamage => 'Theft / damage';

  @override
  String get chainCarrefour => 'Carrefour';

  @override
  String get chainBeitElGomla => 'Beit El Gomla';

  @override
  String get penSelectBranchesFirst =>
      'Select one or more branches to pin as the default';

  @override
  String get penDefaultUnpinned => 'Default branch group unpinned';

  @override
  String get penBranchPinned => 'Branch pinned as the default for fines';

  @override
  String penBranchesPinned(Object count) {
    return '$count branches pinned as the default for fines';
  }

  @override
  String get penSelectDisplayBranches => 'Select branches to show';

  @override
  String get penShowingAllBranches => 'Showing all branches';

  @override
  String penBranchesSelected(Object count) {
    return '$count branches selected';
  }

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get searchBranchName => 'Search by branch name…';

  @override
  String get allBranchesAll => 'All branches';

  @override
  String get selectAll => 'Select all';

  @override
  String get noMatchingBranches => 'No matching branches';

  @override
  String get inDefault => 'In default';

  @override
  String get confirmShowAllBranches => 'Confirm (all branches)';

  @override
  String confirmFilterCount(Object count) {
    return 'Confirm filter ($count branches)';
  }

  @override
  String get finesSection => 'Fines and violations';

  @override
  String get promoNoFinesAccess =>
      'Promotion marketing accounts can\'t access fines and violations';

  @override
  String get myViolationsTitle => 'My violations';

  @override
  String get violationsRecord => 'Violations and fines';

  @override
  String get finesSettings => 'Fines settings and policy';

  @override
  String get recordViolation => 'Record violation';

  @override
  String get unknownCompany => 'Unknown company';

  @override
  String get allBranchesOverview => 'All branches';

  @override
  String selectedGroupCount(Object count) {
    return 'Selected group ($count branches)';
  }

  @override
  String get finesPolicyCardSubtitle =>
      'The deduction for each violation, first time and when repeated';

  @override
  String get showViolationsFor => 'Show violations for branch / group:';

  @override
  String get unpinDefaultGroup => 'Unpin default group';

  @override
  String get pinSelectedAsDefault => 'Pin selected branches as default';

  @override
  String get refreshFinesData => 'Refresh fines data';

  @override
  String get finesDataRefreshed => 'Fines data refreshed';

  @override
  String get pinnedDefaultGroup => 'Pinned default group';

  @override
  String get showAll => 'Show all';

  @override
  String get mySummary => 'Summary';

  @override
  String finesSummaryOf(Object branch) {
    return 'Fines summary ($branch)';
  }

  @override
  String get companiesFinesSummary => 'Fines summary by company';

  @override
  String get finesSummary => 'Fines summary';

  @override
  String get myTotalFines => 'Total fines';

  @override
  String get totalFines => 'Total fines';

  @override
  String get deductedFromMe => 'Deducted';

  @override
  String get deducted => 'Deducted';

  @override
  String get violationsCountLabel => 'Violations';

  @override
  String get companiesCount => 'Companies';

  @override
  String companiesN(Object count) {
    return '$count companies';
  }

  @override
  String get filterByCompany => 'Filter by company:';

  @override
  String allCompaniesCount(Object count) {
    return 'All companies ($count)';
  }

  @override
  String get recordClean => 'Your record is clean!';

  @override
  String get noViolationsAnyCompany =>
      'No violations recorded for any company yet';

  @override
  String get noViolationsThisCompany =>
      'No violations recorded for this company';

  @override
  String get noViolationsRecorded => 'No violations recorded.';

  @override
  String get rejectionReason => 'Rejection reason';

  @override
  String get rejectionReasonHint =>
      'Write the reason for rejecting this violation…';

  @override
  String get confirmRejection => 'Confirm rejection';

  @override
  String get repeatedViolation => 'Repeated violation';

  @override
  String get confidential => 'Confidential';

  @override
  String targetDelegate(Object name) {
    return 'Delegate: $name';
  }

  @override
  String get violationDetails => 'Violation details:';

  @override
  String branchesMarketingApproval(Object name) {
    return 'Branch marketing manager approval: $name';
  }

  @override
  String generalManagerApproval(Object name) {
    return 'General manager approval: $name';
  }

  @override
  String attachmentsCount(Object count) {
    return 'Attachments ($count)';
  }

  @override
  String get tapToPreview2 => 'Tap to preview';

  @override
  String editorName(Object name) {
    return 'Recorded by: $name';
  }

  @override
  String documentsCount(Object count) {
    return 'Documents ($count)';
  }

  @override
  String get approveAction => 'Approve';

  @override
  String get rejectAction => 'Reject';

  @override
  String violationsWithCount(Object count) {
    return 'Violations: $count';
  }

  @override
  String totalWithValue(Object value) {
    return 'Total: $value';
  }

  @override
  String deductedWithValue(Object value) {
    return 'Deducted: $value';
  }

  @override
  String get catUnauthorizedPhoto => 'Photography without permission';

  @override
  String get catDataMissing => 'Missing data / features not enabled';

  @override
  String get catOther => 'Other';

  @override
  String get themeModeTitle => 'Appearance';

  @override
  String get themeModeSystem => 'System default';

  @override
  String get themeModeSystemHint => 'Follows your phone\'s dark theme setting';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get taskImageAttach => 'Attach image';

  @override
  String get taskImageFromCamera => 'Take photo';

  @override
  String get taskImageFromGallery => 'Choose from gallery';

  @override
  String get taskImageReplace => 'Replace image';

  @override
  String get taskImageRemove => 'Remove image';

  @override
  String get taskImageUploading => 'Uploading image…';

  @override
  String get taskImageUploadFailed => 'Couldn\'t upload the image. Try again.';

  @override
  String get taskImageRetry => 'Retry';

  @override
  String get taskImageLoadFailed => 'Couldn\'t load the image';

  @override
  String get taskImageAttached => 'Attached image';

  @override
  String get taskImageTooLarge =>
      'The image is too large. Choose a smaller one.';

  @override
  String get taskImageAttachAnother => 'Attach another image';

  @override
  String get taskImageMaxReached => 'You can attach up to 3 images';

  @override
  String get taskProofTitle => 'Proof of work';

  @override
  String get taskProofAttach => 'Attach proof';

  @override
  String taskProofBy(String name) {
    return 'Proof of work — $name';
  }

  @override
  String get taskProofSave => 'Save proof photos';

  @override
  String get taskEditedLabel => 'Edited';

  @override
  String get taskEditAction => 'Edit';

  @override
  String get taskDeleteAction => 'Delete';

  @override
  String get taskMoreActions => 'Task options';

  @override
  String get taskCloseImage => 'Close';

  @override
  String get splashConnectionFailed => 'Couldn\'t connect';

  @override
  String get splashRetry => 'Retry';

  @override
  String get splashSignIn => 'Sign in';

  @override
  String get mapUnavailable => 'Map unavailable';

  @override
  String get mapRetry => 'Retry';

  @override
  String get deviceLockTitle =>
      'Security alert: this account is bound to another device';

  @override
  String get deviceLockPendingUnbindButton => 'Unbind request pending review';

  @override
  String get deviceLockSendUnbindButton => 'Send an unbind request';

  @override
  String get deviceLockSubmitting => 'Sending request...';

  @override
  String get deviceLockRequestSent => 'The request was sent to the supervisor';

  @override
  String get deviceLockCannotIdentifyDelegate =>
      'Could not identify the delegate to send the request';

  @override
  String deviceLockSendError(String error) {
    return 'Could not send the request: $error';
  }

  @override
  String get chainPickerTitle => 'Target organization / retail chain';

  @override
  String get chainPickerSelectAll => 'Select all';

  @override
  String get chainPickerOneSubscriptionNote =>
      'One request, one approval, and one subscription. There is no per-chain fee.';

  @override
  String get chainPickerRequired => 'Please select at least one chain.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'This version of Tashil is no longer supported. Please install the latest update to continue.';

  @override
  String updateRequiredVersions(String current, String minimum) {
    return 'Installed version $current · minimum $minimum';
  }

  @override
  String get updateRequiredButton => 'Update now';

  @override
  String get updateRequiredNoStoreLink =>
      'Open the App Store and update Tashil, then open the app again.';

  @override
  String get updateRequiredOpenFailed =>
      'Could not open the store. Please open it yourself and update Tashil.';

  @override
  String get profileIdentityEditViaSupervisor =>
      'To change your name or email, please contact your supervisor.';

  @override
  String attYouAreAtChainBranch(String chain, String branch) {
    return 'You are at $chain - $branch';
  }

  @override
  String autoSwitchedToChainBranch(String branch, String chain) {
    return 'You are at $branch — switched to $chain automatically';
  }

  @override
  String get autoSwitchUndo => 'Undo';

  @override
  String autoSwitchPickCompany(String branch, String chain) {
    return 'You are at $branch ($chain). Choose the company';
  }

  @override
  String autoSwitchBlockedActiveSession(String branch, String chain) {
    return 'You are at $branch ($chain), but you have an open check-in. Check out first.';
  }

  @override
  String get phoneChangeTitle => 'Change phone number';

  @override
  String get phoneChangeIntro =>
      'Enter the new number and your national ID. A confirmation code will be sent to the new number.';

  @override
  String get phoneChangeNewPhone => 'New mobile number';

  @override
  String get phoneChangeNationalId => 'National ID';

  @override
  String get phoneChangeSendCode => 'Send code';

  @override
  String phoneChangeCodeSent(String phone) {
    return 'Enter the code sent to $phone';
  }

  @override
  String get phoneChangeCodeLabel => 'Confirmation code';

  @override
  String get phoneChangeConfirm => 'Confirm';

  @override
  String get phoneChangeResend => 'Resend code';

  @override
  String get phoneChangeDone =>
      'Your phone number was changed. Use the new number to sign in from now on.';

  @override
  String get phoneChangeErrBadPhone =>
      'Enter a valid Egyptian or UAE mobile number.';

  @override
  String get phoneChangeErrNationalId =>
      'The national ID does not match your profile.';

  @override
  String get phoneChangeErrSamePhone => 'This is already your number.';

  @override
  String get phoneChangeErrTaken => 'This number belongs to another account.';

  @override
  String get phoneChangeErrTooMany =>
      'Too many attempts today. Try again tomorrow.';

  @override
  String get phoneChangeErrExpired => 'The request expired. Start again.';

  @override
  String get phoneChangeErrWrongCode => 'Wrong code. Check it and try again.';

  @override
  String get phoneChangeErrGeneric =>
      'Something went wrong. Try again in a moment.';

  @override
  String get countryEgypt => 'Egypt';

  @override
  String get countryUae => 'United Arab Emirates';

  @override
  String get phoneCountryLabel => 'Country code';

  @override
  String get locHelpTitle => 'Location not working? Try these steps';

  @override
  String get locHelpOpenLocationSettings => 'Open location settings';

  @override
  String get locHelpOpenAppSettings => 'Open app settings';

  @override
  String get locHelpRetry => 'Check location again';

  @override
  String get locHelpStepGoogleAccuracy =>
      'Turn on “Google Location Accuracy” in location settings.';

  @override
  String get locHelpStepPermission =>
      'Give the app location permission “While using the app” with “Precise location”.';

  @override
  String get locHelpStepBattery =>
      'Take Tashil out of battery saving and set it to “Unrestricted” (important on OPPO, Realme and Xiaomi).';

  @override
  String get attFetchingLocation => 'Fetching location...';

  @override
  String get locHelpStepMapsRetry =>
      'Still no location: open Google Maps, wait for the blue dot to settle, then come back and tap “Check location again”.';

  @override
  String get locHelpStepMapsTryAgain =>
      'Still no location: open Google Maps, wait for the blue dot to settle, then come back and try again.';

  @override
  String attBranchOtherChain(String chain) {
    return 'This branch belongs to $chain. Switch to that chain first, then try again.';
  }

  @override
  String get attBranchNotYourChain =>
      'This branch is not in any of your chains. Scan your own branch\'s code.';
}
