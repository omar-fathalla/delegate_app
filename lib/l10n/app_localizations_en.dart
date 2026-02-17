// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tashil - Delegate';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get loginToContinue => 'Login to continue';

  @override
  String get loginSuccessful => 'Login Successful!';

  @override
  String get loginButton => 'LOGIN';

  @override
  String get mobileNumber => 'Mobile Number';

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
}
