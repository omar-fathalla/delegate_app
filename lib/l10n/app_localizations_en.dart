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
  String get delegateApp => 'Delegate App';

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
    return 'Scan for $action';
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
  String get helpCenter => 'Help Center';

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
  String get openInBrowser => 'Open in browser';

  @override
  String get showPassword => 'Show Password';

  @override
  String get hidePassword => 'Hide Password';
}
