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
  String get logout => 'Logout';

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
      'This account is pending or suspended. Contact your company admin.';

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
  String get scanQrInstruction =>
      'Scan the QR code located in the marketing office.';

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
  String get noHistoryAvailable => 'No history available';

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
  String get locationPermissionDenied => 'Location permission denied.';

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
  String get darkMode => 'Dark Mode';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get helpCenter => 'Help center';

  @override
  String version(String version) {
    return 'Tashil Representative - Version $version';
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
  String get taskInProgress => 'In Progress';

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
  String get whatsNewTitle => 'What\'s new?';

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
  String get reqEmptyHint =>
      'Tap \"New request\" to send one to your supervisor';

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
  String get annualBalance21 => 'Annual balance: 21 days';

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
  String get roleFieldDelegate => 'Field delegate';

  @override
  String get roleFieldSupervisor => 'Field supervisor';

  @override
  String get homeCoreDuties => 'Your core duties';

  @override
  String get homeDutyAttendance => 'Check in and out from the branch location.';

  @override
  String get homeDutyTasks => 'Complete and track your daily tasks.';

  @override
  String get homeDutyPhotos =>
      'Photograph offers and brands in hypermarkets and branches.';

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
  String get offerPhotosSubtitle =>
      'Take and upload approved offer photos in the hypermarket';

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
  String leavesOfFour(Object count) {
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
  String get recentBranchActivity => 'Recent branch activity';

  @override
  String get viewLog => 'View log';

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
  String noSupervisorForCompany(Object companyUID) {
    return 'No supervisor registered for this company yet\n(Company ID: $companyUID)';
  }

  @override
  String pendingCountBadge(Object count) {
    return '$count pending';
  }

  @override
  String get orgMarketing => 'Marketing';

  @override
  String get orgAdminPanel => 'Admin panel';

  @override
  String get orgAccounting => 'Accounting';

  @override
  String switchedToOrg(Object orgLabel) {
    return 'Switched to $orgLabel';
  }

  @override
  String get unknownOrganization => 'Unknown organization';

  @override
  String get alreadyInOrg => 'You\'re already in this organization.';

  @override
  String get logoutAction => 'Log out';

  @override
  String get logoutConfirm => 'Log out?\nYour local data will be saved first.';

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
  String get attVerifyingCoords =>
      'Verifying your location and distance to the branch';

  @override
  String get attInsideZone => 'Inside work zone';

  @override
  String attWithinBranchRange(Object branch) {
    return 'Within range of $branch';
  }

  @override
  String get attWithinAllowedRange => 'Within allowed range';

  @override
  String get attOutsideZone => 'Outside work zone';

  @override
  String attMoveCloserTo(Object branch) {
    return 'Move closer to $branch to check in';
  }

  @override
  String get attOutsideApprovedBranches => 'Outside approved branches';

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
    return 'Radius: $allowedRadius m';
  }

  @override
  String get recheckLocation => 'Recheck location';

  @override
  String get activeChain => 'Current chain';

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
  String get showAllChains => 'Show all chains';

  @override
  String get attAutoClosedNote =>
      'Checked out automatically 9 hours after the shift started, since no check-out was recorded';

  @override
  String get autoClosed9h => 'Auto-closed (9h)';

  @override
  String get checkOut2 => 'Check out';

  @override
  String get attCheckingLocation => 'Checking location…';

  @override
  String get checkIn2 => 'Check in';

  @override
  String get noBranchesForOrgYet =>
      'No branches registered for this organization yet.';

  @override
  String get noBranchesForOrg =>
      'No branches registered for this organization.';

  @override
  String attYouAreWithinBranch(Object branch) {
    return 'You are within range of $branch';
  }

  @override
  String get attMoveCloser => 'Move closer to the branch to check in';

  @override
  String get attOutsideApproved => 'You are outside approved branches';

  @override
  String get attCheckInSavedOffline =>
      'Check-in saved on this device. It will sync when you are back online.';

  @override
  String get attCheckOutSavedOffline =>
      'Check-out saved on this device. It will sync when you are back online.';

  @override
  String get syncDone => 'Synced';

  @override
  String get syncFailed => 'Sync failed';

  @override
  String attDelegateOfCompany(Object companyName) {
    return 'Delegate · $companyName';
  }

  @override
  String get attendanceLog => 'Attendance log';

  @override
  String distanceMeters(Object meters) {
    return '$meters m';
  }

  @override
  String get attLocatingYou => 'Finding your location and checking branches…';

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
  String metersValue(Object value) {
    return '$value m';
  }

  @override
  String attCannotActOutside(Object action, Object distance) {
    return 'You can\'t $action while outside the branch ($distance). Please be inside the branch.';
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
      'Location permission is permanently denied.';

  @override
  String get fakeGpsDetected =>
      'A fake GPS app was detected. Turn it off to check in and out.';

  @override
  String get locationTimeout =>
      'Timed out getting your location. Make sure GPS is on and you\'re in an open area.';

  @override
  String get locationError =>
      'Something went wrong while getting your location.';

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
  String get profilePhotoDeleted => 'Profile photo removed';

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
  String get removeCurrentPhoto => 'Remove current photo';

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
}
