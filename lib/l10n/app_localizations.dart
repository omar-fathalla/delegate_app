import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// App title
  ///
  /// In en, this message translates to:
  /// **'Tashil'**
  String get appTitle;

  /// Employees app subtitle
  ///
  /// In en, this message translates to:
  /// **'Employees App'**
  String get delegateApp;

  /// Login label
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// Logout label
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// Login subtitle
  ///
  /// In en, this message translates to:
  /// **'Welcome back, please enter your details'**
  String get loginToContinue;

  /// Login success snackbar
  ///
  /// In en, this message translates to:
  /// **'Login Successful!'**
  String get loginSuccessful;

  /// Login button text
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// Mobile number field label
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get mobileNumber;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Mother name field label
  ///
  /// In en, this message translates to:
  /// **'Mother\'s Name'**
  String get motherName;

  /// Mobile validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter mobile number'**
  String get enterMobileNumber;

  /// Password validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter password'**
  String get enterPassword;

  /// Delegate login national ID field label
  ///
  /// In en, this message translates to:
  /// **'National ID number'**
  String get nationalIdNumber;

  /// Empty national ID validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter the national ID number'**
  String get enterNationalId;

  /// National ID format validation error
  ///
  /// In en, this message translates to:
  /// **'National ID must be 14 digits'**
  String get invalidNationalId;

  /// Mobile number format validation error
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number'**
  String get invalidMobileNumber;

  /// Helper under the delegate login secret field
  ///
  /// In en, this message translates to:
  /// **'Delegates sign in with their national ID. Other roles use their password.'**
  String get loginNationalIdHelp;

  /// Delegate credential mismatch
  ///
  /// In en, this message translates to:
  /// **'The phone number, national ID, or password is incorrect.'**
  String get invalidLoginCredentials;

  /// Pending or blocked delegate login error
  ///
  /// In en, this message translates to:
  /// **'This account is pending or suspended. Contact your company admin.'**
  String get delegateAccountInactive;

  /// Delegate login lockout message
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get tooManyLoginAttempts;

  /// Delegate login service unavailable
  ///
  /// In en, this message translates to:
  /// **'Sign-in is temporarily unavailable. Please try again.'**
  String get loginTemporarilyUnavailable;

  /// Remember me checkbox label
  ///
  /// In en, this message translates to:
  /// **'Remember Me'**
  String get rememberMe;

  /// Home nav label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Profile nav label
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Attendance nav label
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendance;

  /// Profile screen title
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// Personal info section title
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// Delegate ID label
  ///
  /// In en, this message translates to:
  /// **'Delegate ID'**
  String get delegateId;

  /// Delegate role label
  ///
  /// In en, this message translates to:
  /// **'Delegate'**
  String get delegateRole;

  /// Check in action
  ///
  /// In en, this message translates to:
  /// **'Check In'**
  String get checkIn;

  /// Check out action
  ///
  /// In en, this message translates to:
  /// **'Check Out'**
  String get checkOut;

  /// Check in success message
  ///
  /// In en, this message translates to:
  /// **'Checked In Successfully'**
  String get checkedInSuccessfully;

  /// Check out success message
  ///
  /// In en, this message translates to:
  /// **'Checked Out Successfully'**
  String get checkedOutSuccessfully;

  /// FAB label for check in
  ///
  /// In en, this message translates to:
  /// **'Scan to Check In'**
  String get scanToCheckIn;

  /// FAB label for check out
  ///
  /// In en, this message translates to:
  /// **'Scan to Check Out'**
  String get scanToCheckOut;

  /// Instruction to scan QR on empty history screen
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code located in the marketing office.'**
  String get scanQrInstruction;

  /// QR scanner title
  ///
  /// In en, this message translates to:
  /// **'Scan to {action}'**
  String scanForAction(String action);

  /// QR scanner instruction
  ///
  /// In en, this message translates to:
  /// **'Point camera at QR Code for {action}'**
  String pointCameraToQR(String action);

  /// Check in at branch snackbar
  ///
  /// In en, this message translates to:
  /// **'Checking in at {branch}...'**
  String checkingInAt(String branch);

  /// Invalid QR error
  ///
  /// In en, this message translates to:
  /// **'Invalid QR Code. Please scan a valid branch code.'**
  String get invalidQRCode;

  /// Status card title
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get currentStatus;

  /// Online status
  ///
  /// In en, this message translates to:
  /// **'ONLINE'**
  String get online;

  /// Offline status
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get offline;

  /// Active check-in indicator
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// Check in time label
  ///
  /// In en, this message translates to:
  /// **'In: {time}'**
  String inLabel(String time);

  /// Check out time label
  ///
  /// In en, this message translates to:
  /// **'Out: {time}'**
  String outLabel(String time);

  /// Empty month message
  ///
  /// In en, this message translates to:
  /// **'No attendance records for {month}'**
  String noRecordsForMonth(String month);

  /// History section title
  ///
  /// In en, this message translates to:
  /// **'Recent History'**
  String get recentHistory;

  /// Empty history message
  ///
  /// In en, this message translates to:
  /// **'No history available'**
  String get noHistoryAvailable;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// Fallback branch name
  ///
  /// In en, this message translates to:
  /// **'Unspecified'**
  String get unspecifiedBranch;

  /// Greeting with user name
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String helloUser(String name);

  /// History row in/out label
  ///
  /// In en, this message translates to:
  /// **'In: {inTime} - Out: {outTime}'**
  String historyInOut(String inTime, String outTime);

  /// General error
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again.'**
  String get errorGeneral;

  /// Network error
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get errorNetwork;

  /// Location error
  ///
  /// In en, this message translates to:
  /// **'Could not determine your location.'**
  String get errorLocation;

  /// Out of range error
  ///
  /// In en, this message translates to:
  /// **'You are outside the worksite range.'**
  String get errorOutOfRange;

  /// Mock location error
  ///
  /// In en, this message translates to:
  /// **'Mock location detected. Cannot check in.'**
  String get errorMockLocation;

  /// Auth error
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials.'**
  String get errorAuth;

  /// Success message
  ///
  /// In en, this message translates to:
  /// **'Operation completed successfully'**
  String get success;

  /// Loading indicator
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Pending sync indicator
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get pendingSync;

  /// Settings menu title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Companies tab label
  ///
  /// In en, this message translates to:
  /// **'Companies'**
  String get companies;

  /// Search tab label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Language menu item
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Change language menu item
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// Arabic language name
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// English language name
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// Language changed confirmation
  ///
  /// In en, this message translates to:
  /// **'Language changed to {language}'**
  String languageChangedTo(String language);

  /// Duration in hours and minutes
  ///
  /// In en, this message translates to:
  /// **'Duration: {hours}h {minutes}m'**
  String duration(String hours, String minutes);

  /// Ongoing session indicator
  ///
  /// In en, this message translates to:
  /// **'In progress...'**
  String get inProgress;

  /// Full name label
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// Phone number label
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// Birth date label
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get birthDate;

  /// City label
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityLabel;

  /// Organization and company section title
  ///
  /// In en, this message translates to:
  /// **'Organization & Company'**
  String get organizationAndCompany;

  /// Organization label
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organizationLabel;

  /// Company label
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get companyLabel;

  /// Position label
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get positionLabel;

  /// Documents tab label
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// Request history tab label
  ///
  /// In en, this message translates to:
  /// **'Request History'**
  String get requestHistory;

  /// Personal photo document
  ///
  /// In en, this message translates to:
  /// **'Personal Photo'**
  String get personalPhoto;

  /// National ID document
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get nationalId;

  /// Authorization letter document
  ///
  /// In en, this message translates to:
  /// **'Authorization Letter'**
  String get authorizationLetter;

  /// Insurance letter document
  ///
  /// In en, this message translates to:
  /// **'Insurance Letter'**
  String get insuranceLetter;

  /// Health certificate document
  ///
  /// In en, this message translates to:
  /// **'Health Certificate'**
  String get healthCertificate;

  /// Payment receipt document
  ///
  /// In en, this message translates to:
  /// **'Payment Receipt'**
  String get paymentReceipt;

  /// Electronic payment receipt document
  ///
  /// In en, this message translates to:
  /// **'Electronic Payment Receipt'**
  String get electronicPaymentReceipt;

  /// Pending status label
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingStatus;

  /// Upload date label
  ///
  /// In en, this message translates to:
  /// **'Uploaded: {date}'**
  String uploadedOn(String date);

  /// Click to view link
  ///
  /// In en, this message translates to:
  /// **'Click to View'**
  String get clickToView;

  /// Receipt code label
  ///
  /// In en, this message translates to:
  /// **'Receipt Code: {code}'**
  String receiptCode(String code);

  /// Empty request history message
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get noRequestsYet;

  /// Approved status label
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvedStatus;

  /// Rejected status label
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedStatus;

  /// Empty documents message
  ///
  /// In en, this message translates to:
  /// **'No documents uploaded'**
  String get noDocumentsUploaded;

  /// Retry button text
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Gender label
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// Male gender
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// Female gender
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// Join date label
  ///
  /// In en, this message translates to:
  /// **'Join Date'**
  String get joinDate;

  /// Employment details section title
  ///
  /// In en, this message translates to:
  /// **'Employment Details'**
  String get employmentDetails;

  /// Status reason label
  ///
  /// In en, this message translates to:
  /// **'Status Reason'**
  String get statusReason;

  /// Profile complete status
  ///
  /// In en, this message translates to:
  /// **'Profile Complete'**
  String get profileComplete;

  /// Profile incomplete status
  ///
  /// In en, this message translates to:
  /// **'Profile Incomplete'**
  String get profileIncomplete;

  /// Reviewer name label
  ///
  /// In en, this message translates to:
  /// **'Reviewed By: {name}'**
  String reviewedBy(String name);

  /// Not provided document status
  ///
  /// In en, this message translates to:
  /// **'Not Provided'**
  String get notProvidedStatus;

  /// Admin dashboard title
  ///
  /// In en, this message translates to:
  /// **'Admin Dashboard'**
  String get adminDashboard;

  /// Add new branch title
  ///
  /// In en, this message translates to:
  /// **'Add New Branch'**
  String get addBranch;

  /// Branch name label
  ///
  /// In en, this message translates to:
  /// **'Branch Name'**
  String get branchName;

  /// Branch location label
  ///
  /// In en, this message translates to:
  /// **'Branch Location'**
  String get branchLocation;

  /// Geofence radius label
  ///
  /// In en, this message translates to:
  /// **'Attendance Radius (Meters)'**
  String get geofenceRadius;

  /// Save branch button
  ///
  /// In en, this message translates to:
  /// **'Save Branch'**
  String get saveBranch;

  /// Branch added success message
  ///
  /// In en, this message translates to:
  /// **'Branch Added Successfully'**
  String get branchAddedSuccessfully;

  /// Branch name required validation
  ///
  /// In en, this message translates to:
  /// **'Please enter branch name'**
  String get pleaseEnterBranchName;

  /// Location required validation
  ///
  /// In en, this message translates to:
  /// **'Please select a location on the map'**
  String get pleaseSelectLocation;

  /// Search bar hint
  ///
  /// In en, this message translates to:
  /// **'Search city or region...'**
  String get searchCityOrRegion;

  /// Label for the branches tab in the admin dashboard navigation.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get branches;

  /// Role title for branch marketing staff
  ///
  /// In en, this message translates to:
  /// **'Branch Marketing'**
  String get roleBranchMarketing;

  /// Role title for branches marketing manager
  ///
  /// In en, this message translates to:
  /// **'Branches Marketing Manager'**
  String get roleBranchesMarketingManager;

  /// Short label for branches marketing manager
  ///
  /// In en, this message translates to:
  /// **'Branches Marketing Mgr'**
  String get roleBranchesMarketingMgrShort;

  /// Role title for marketing promotion staff
  ///
  /// In en, this message translates to:
  /// **'Marketing Promotion'**
  String get roleMarketingPromotion;

  /// Subtitle for branch marketing follow-up
  ///
  /// In en, this message translates to:
  /// **'Branch Marketing Follow-up'**
  String get branchMarketingFollowUp;

  /// Subtitle for branch marketing coordination
  ///
  /// In en, this message translates to:
  /// **'Branch Marketing Coordination'**
  String get branchMarketingCoordination;

  /// Label for the admin dashboard title.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// Label for the fetch current location button.
  ///
  /// In en, this message translates to:
  /// **'My Location'**
  String get myLocation;

  /// Error when GPS is disabled.
  ///
  /// In en, this message translates to:
  /// **'Location services are disabled.'**
  String get locationServicesDisabled;

  /// Error when location permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied.'**
  String get locationPermissionDenied;

  /// Generic error when fetching location fails.
  ///
  /// In en, this message translates to:
  /// **'Error fetching location.'**
  String get errorFetchingLocation;

  /// Title for the branch details screen.
  ///
  /// In en, this message translates to:
  /// **'Branch Details'**
  String get branchDetails;

  /// Button to download the QR code.
  ///
  /// In en, this message translates to:
  /// **'Download QR'**
  String get downloadQR;

  /// Message shown when QR is saved to gallery
  ///
  /// In en, this message translates to:
  /// **'QR Code saved to gallery successfully!'**
  String get qrSavedToGallery;

  /// Button to edit the branch name.
  ///
  /// In en, this message translates to:
  /// **'Edit Name'**
  String get editName;

  /// Button to edit the branch details.
  ///
  /// In en, this message translates to:
  /// **'Edit Branch'**
  String get editBranch;

  /// Success message after updating a branch.
  ///
  /// In en, this message translates to:
  /// **'Branch updated successfully.'**
  String get branchUpdatedSuccessfully;

  /// Button to delete the branch.
  ///
  /// In en, this message translates to:
  /// **'Delete Branch'**
  String get deleteBranch;

  /// Confirmation message before deleting a branch.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this branch?'**
  String get deleteBranchConfirmation;

  /// Success message after deleting a branch.
  ///
  /// In en, this message translates to:
  /// **'Branch deleted successfully.'**
  String get branchDeletedSuccessfully;

  /// Button to save edited branch name.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// Offline network status indicator
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get networkStatusOffline;

  /// Online network status indicator
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get networkStatusOnline;

  /// No account contact text on login screen
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Contact the following number'**
  String get noAccountContact;

  /// No account title text on login screen
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccountTitle;

  /// No account subtitle text on login screen
  ///
  /// In en, this message translates to:
  /// **'Contact the following number'**
  String get noAccountSubtitle;

  /// Contact phone number
  ///
  /// In en, this message translates to:
  /// **'01211857725'**
  String get contactNumber;

  /// Dark mode setting label
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// Privacy policy setting label
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// Help center setting label
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get helpCenter;

  /// App version label in settings
  ///
  /// In en, this message translates to:
  /// **'Tashil Representative - Version {version}'**
  String version(String version);

  /// Account section header
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// Main privacy policy description
  ///
  /// In en, this message translates to:
  /// **'This Privacy Policy describes how we collect, use, and disclose your personal information when you use our delegate services. We are committed to protecting your privacy and ensuring your data is handled securely.'**
  String get privacyPolicyDesc;

  /// Location data section title
  ///
  /// In en, this message translates to:
  /// **'LOCATION DATA'**
  String get locationData;

  /// Location data section description
  ///
  /// In en, this message translates to:
  /// **'Our app collects location data to enable real-time tracking of deliveries and to match delegates with nearby orders even when the app is closed or not in use. This data is essential for the core functionality of our service.'**
  String get locationDataDesc;

  /// Camera access section title
  ///
  /// In en, this message translates to:
  /// **'CAMERA ACCESS'**
  String get cameraAccess;

  /// Camera access section description
  ///
  /// In en, this message translates to:
  /// **'We require camera access to allow you to take photos of bills, packages, or delivery proofs. Photos are only captured when you explicitly use the camera feature within the app.'**
  String get cameraAccessDesc;

  /// Data security section title
  ///
  /// In en, this message translates to:
  /// **'DATA SECURITY'**
  String get dataSecurity;

  /// Data security section description
  ///
  /// In en, this message translates to:
  /// **'We implement industry-standard security measures to protect your data. We do not sell your personal data. Your information is shared only with authorized partners for service processing.'**
  String get dataSecurityDesc;

  /// Contact Us section title
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactUs;

  /// Website label
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// Email address label
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// Egypt office label
  ///
  /// In en, this message translates to:
  /// **'Egypt Office'**
  String get egyptOffice;

  /// UAE office label
  ///
  /// In en, this message translates to:
  /// **'UAE Office'**
  String get uaeOffice;

  /// SwitchPoint website value
  ///
  /// In en, this message translates to:
  /// **'https://sw-point.com/'**
  String get swPointWebsite;

  /// SwitchPoint support email value
  ///
  /// In en, this message translates to:
  /// **'support@sw-point.com'**
  String get swPointEmail;

  /// SwitchPoint Egypt phone value
  ///
  /// In en, this message translates to:
  /// **'Alexandria, Egypt +20 121 185 7725'**
  String get swPointEgyptPhone;

  /// SwitchPoint UAE phone value
  ///
  /// In en, this message translates to:
  /// **'United Arab Emirates WhatsApp: +971 55 871 5615'**
  String get swPointUaePhone;

  /// Create admin screen title and button
  ///
  /// In en, this message translates to:
  /// **'Create Admin'**
  String get createAdmin;

  /// Admin name field label
  ///
  /// In en, this message translates to:
  /// **'Admin Name'**
  String get adminName;

  /// Admin phone field label
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get adminPhone;

  /// Admin email field label
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get adminEmail;

  /// Admin name validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter admin name'**
  String get pleaseEnterAdminName;

  /// Admin phone validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter phone number'**
  String get pleaseEnterAdminPhone;

  /// Admin email validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter email address'**
  String get pleaseEnterAdminEmail;

  /// Invalid phone number validation error
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number'**
  String get invalidPhoneNumber;

  /// Invalid email validation error
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmail;

  /// Admin created success message
  ///
  /// In en, this message translates to:
  /// **'Admin account created successfully! Activation email sent.'**
  String get adminCreatedSuccessfully;

  /// Manage admins menu item
  ///
  /// In en, this message translates to:
  /// **'Manage Admins'**
  String get manageAdmins;

  /// Empty admins list message
  ///
  /// In en, this message translates to:
  /// **'No admins found'**
  String get noAdminsFound;

  /// Suspended status badge
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended;

  /// Edit admin action
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAdmin;

  /// Delete admin action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAdmin;

  /// Suspend admin action
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get suspendAdmin;

  /// Activate admin action
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activateAdmin;

  /// Delete admin confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this admin? This action cannot be undone.'**
  String get deleteAdminConfirmation;

  /// Cancel button text
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Company delegates screen title
  ///
  /// In en, this message translates to:
  /// **'Delegates'**
  String get companyDelegates;

  /// View attendance button
  ///
  /// In en, this message translates to:
  /// **'View Attendance'**
  String get viewAttendance;

  /// Empty delegates list message
  ///
  /// In en, this message translates to:
  /// **'No delegates found'**
  String get noDelegatesFound;

  /// View profile data button text
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfileData;

  /// Add delegate button text
  ///
  /// In en, this message translates to:
  /// **'Add Delegate'**
  String get addDelegate;

  /// Add delegate via web title
  ///
  /// In en, this message translates to:
  /// **'Add via Web'**
  String get addDelegateViaWeb;

  /// Tasks tab or screen title
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// Dashboard section title
  ///
  /// In en, this message translates to:
  /// **'Today\'s Overview'**
  String get todayOverview;

  /// Total delegates card title
  ///
  /// In en, this message translates to:
  /// **'Total Delegates'**
  String get totalDelegates;

  /// Checked in today card title
  ///
  /// In en, this message translates to:
  /// **'Checked In Today'**
  String get checkedInToday;

  /// Absent today card title
  ///
  /// In en, this message translates to:
  /// **'Absent Today'**
  String get absentToday;

  /// Button text to add a new task
  ///
  /// In en, this message translates to:
  /// **'Add Task'**
  String get addTask;

  /// Label for task title input
  ///
  /// In en, this message translates to:
  /// **'Task Title'**
  String get taskTitle;

  /// Label for task description input
  ///
  /// In en, this message translates to:
  /// **'Task Description'**
  String get taskDescription;

  /// Label for task priority selection
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get taskPriority;

  /// High priority label
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// Medium priority label
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// Low priority label
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// Label for task due date input
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get taskDueDate;

  /// Label for assigning task to a delegate
  ///
  /// In en, this message translates to:
  /// **'Assign To'**
  String get assignTo;

  /// Option for assigning task to all delegates
  ///
  /// In en, this message translates to:
  /// **'All Delegates'**
  String get allDelegates;

  /// Button text to create a task
  ///
  /// In en, this message translates to:
  /// **'Create Task'**
  String get createTask;

  /// Success message after creating a task
  ///
  /// In en, this message translates to:
  /// **'Task created successfully'**
  String get taskCreatedSuccessfully;

  /// Success message after updating a task
  ///
  /// In en, this message translates to:
  /// **'Task updated successfully'**
  String get taskUpdatedSuccessfully;

  /// Message shown when no tasks match the filter
  ///
  /// In en, this message translates to:
  /// **'No tasks found'**
  String get noTasksFound;

  /// Label for task status selection
  ///
  /// In en, this message translates to:
  /// **'Task Status'**
  String get taskStatus;

  /// Pending task status label
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taskPending;

  /// In Progress task status label
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get taskInProgress;

  /// Completed task status label
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskCompleted;

  /// Filter option for all items
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Today label
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Yesterday label
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Cancelled task status label
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get taskCancelled;

  /// Task details title
  ///
  /// In en, this message translates to:
  /// **'Task Details'**
  String get taskDetails;

  /// Task schedule title
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get taskSchedule;

  /// Select delegate label
  ///
  /// In en, this message translates to:
  /// **'Select Delegate'**
  String get selectDelegate;

  /// Validation error for required field
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get errorFieldRequired;

  /// Message when no tasks are found and user is prompted to add one
  ///
  /// In en, this message translates to:
  /// **'Add a task to get started'**
  String get addTaskToGetStarted;

  /// Title for the delegate's tasks screen
  ///
  /// In en, this message translates to:
  /// **'My Tasks'**
  String get myTasks;

  /// Message when no tasks are assigned to the delegate
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get noTasksYet;

  /// Button text to complete a task
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get complete;

  /// General delete button text
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Title for delete task dialog/button
  ///
  /// In en, this message translates to:
  /// **'Delete Task'**
  String get deleteTask;

  /// Confirmation message for deleting a task
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this task? This action cannot be undone.'**
  String get deleteTaskConfirmation;

  /// Label for task notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// Title for the task summary card on home screen
  ///
  /// In en, this message translates to:
  /// **'Tasks Summary'**
  String get tasksSummary;

  /// Label for total count
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// Placeholder for searching delegates
  ///
  /// In en, this message translates to:
  /// **'Search delegates...'**
  String get searchDelegates;

  /// Label for status filter
  ///
  /// In en, this message translates to:
  /// **'Filter by status'**
  String get filterByStatus;

  /// Message shown when no delegates match search or filter
  ///
  /// In en, this message translates to:
  /// **'No delegates match your search'**
  String get noDelegateSearchResults;

  /// Notifications page title
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// Message when there are no notifications
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// Button to mark all notifications as read
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// New notification label
  ///
  /// In en, this message translates to:
  /// **'New notification'**
  String get newNotification;

  /// Search companies screen title
  ///
  /// In en, this message translates to:
  /// **'Search Companies'**
  String get searchCompanies;

  /// Hint text for company search
  ///
  /// In en, this message translates to:
  /// **'Search for companies using company code'**
  String get searchCompaniesHint;

  /// Placeholder for company code search input
  ///
  /// In en, this message translates to:
  /// **'Enter company code'**
  String get enterCompanyCode;

  /// Clear button text
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Message when no companies are found
  ///
  /// In en, this message translates to:
  /// **'No companies found'**
  String get noCompaniesFound;

  /// Search query label
  ///
  /// In en, this message translates to:
  /// **'Search Query'**
  String get searchQuery;

  /// Error occurred message
  ///
  /// In en, this message translates to:
  /// **'Error Occurred'**
  String get errorOccurred;

  /// Try again button text
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// Manage marketing employees menu item
  ///
  /// In en, this message translates to:
  /// **'Manage Marketing Employees'**
  String get manageMarketing;

  /// Empty marketing employees list message
  ///
  /// In en, this message translates to:
  /// **'No marketing employees found'**
  String get noMarketingEmployeesFound;

  /// Search by phone number placeholder
  ///
  /// In en, this message translates to:
  /// **'Search by phone number...'**
  String get searchByPhone;

  /// Filter by organization label
  ///
  /// In en, this message translates to:
  /// **'Filter by organization'**
  String get filterByOrganization;

  /// All organizations filter option
  ///
  /// In en, this message translates to:
  /// **'All Organizations'**
  String get allOrganizations;

  /// Marketing employee label
  ///
  /// In en, this message translates to:
  /// **'Marketing Employee'**
  String get marketingEmployee;

  /// Edit marketing employee action
  ///
  /// In en, this message translates to:
  /// **'Edit Employee'**
  String get editMarketingEmployee;

  /// Delete marketing employee action
  ///
  /// In en, this message translates to:
  /// **'Delete Employee'**
  String get deleteMarketingEmployee;

  /// Delete marketing employee confirmation
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this employee? This action cannot be undone.'**
  String get deleteMarketingEmployeeConfirmation;

  /// Suspend marketing employee action
  ///
  /// In en, this message translates to:
  /// **'Suspend Employee'**
  String get suspendMarketingEmployee;

  /// Activate marketing employee action
  ///
  /// In en, this message translates to:
  /// **'Activate Employee'**
  String get activateMarketingEmployee;

  /// Employee suspended success message
  ///
  /// In en, this message translates to:
  /// **'Employee suspended'**
  String get employeeSuspended;

  /// Employee activated success message
  ///
  /// In en, this message translates to:
  /// **'Employee activated'**
  String get employeeActivated;

  /// Employee deleted success message
  ///
  /// In en, this message translates to:
  /// **'Employee deleted successfully'**
  String get employeeDeleted;

  /// Employee updated success message
  ///
  /// In en, this message translates to:
  /// **'Employee updated successfully'**
  String get employeeUpdated;

  /// Employee name field label
  ///
  /// In en, this message translates to:
  /// **'Employee Name'**
  String get employeeName;

  /// Employee phone field label
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get employeePhone;

  /// Employee email field label
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get employeeEmail;

  /// Organization label
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organization;

  /// Title for forgot checkout dialog
  ///
  /// In en, this message translates to:
  /// **'Pending Check-in Alert'**
  String get forgotCheckoutTitle;

  /// Message for forgot checkout in a different branch
  ///
  /// In en, this message translates to:
  /// **'You have a pending check-in at {oldBranch}. Do you want to check out from it and check in to {newBranch}?'**
  String forgotCheckoutMessage(String oldBranch, String newBranch);

  /// Message for forgot checkout from a previous day
  ///
  /// In en, this message translates to:
  /// **'You have a pending check-in from a previous day at {oldBranch}. The system will check you out from it and check you in today at {newBranch}.'**
  String previousDayCheckoutMessage(String oldBranch, String newBranch);

  /// Confirm button text
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// Photo permissions section or screen title
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photoPermissions;

  /// Description of photo permissions feature
  ///
  /// In en, this message translates to:
  /// **'Manage photo permissions and view photo reports'**
  String get photoPermissionsDesc;

  /// Supervisor role label
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get supervisor;

  /// Supervisor greeting label
  ///
  /// In en, this message translates to:
  /// **'Supervisor: {name}'**
  String supervisorUser(String name);

  /// Admin greeting label
  ///
  /// In en, this message translates to:
  /// **'Admin: {name}'**
  String adminUser(String name);

  /// Payment receipts upload report screen title
  ///
  /// In en, this message translates to:
  /// **'Payment Receipts Billing Report'**
  String get paymentReceiptsReport;

  /// Uploaded receipts count label
  ///
  /// In en, this message translates to:
  /// **'Uploads Count'**
  String get uploadsCount;

  /// Total uploaded receipts summary label
  ///
  /// In en, this message translates to:
  /// **'Total Uploaded Receipts'**
  String get totalUploadedReceipts;

  /// Companies with uploaded receipts summary label
  ///
  /// In en, this message translates to:
  /// **'Billed Companies'**
  String get companiesWithUploads;

  /// Receipts report menu item text
  ///
  /// In en, this message translates to:
  /// **'Receipts Report'**
  String get receiptsReport;

  /// Accountant role title
  ///
  /// In en, this message translates to:
  /// **'Financial Accountant'**
  String get accountant;

  /// Accountant dashboard title
  ///
  /// In en, this message translates to:
  /// **'Financial Management Dashboard'**
  String get accountantDashboard;

  /// Financial reports label
  ///
  /// In en, this message translates to:
  /// **'Financial Reports'**
  String get financialReports;

  /// Payment receipts label
  ///
  /// In en, this message translates to:
  /// **'Payment Receipts'**
  String get paymentReceipts;

  /// Subscription requests label
  ///
  /// In en, this message translates to:
  /// **'Subscription Requests'**
  String get subscriptionRequests;

  /// Wallets management label
  ///
  /// In en, this message translates to:
  /// **'Wallets Management'**
  String get walletsManagement;

  /// No description provided for @violationsPolicy.
  ///
  /// In en, this message translates to:
  /// **'Violations policy'**
  String get violationsPolicy;

  /// No description provided for @myViolations.
  ///
  /// In en, this message translates to:
  /// **'My violations'**
  String get myViolations;

  /// No description provided for @switchOrganization.
  ///
  /// In en, this message translates to:
  /// **'Switch organization'**
  String get switchOrganization;

  /// No description provided for @manageOrganizationsChains.
  ///
  /// In en, this message translates to:
  /// **'Manage organizations and chains'**
  String get manageOrganizationsChains;

  /// No description provided for @delegateSubscriptionsMenu.
  ///
  /// In en, this message translates to:
  /// **'Delegate subscriptions'**
  String get delegateSubscriptionsMenu;

  /// No description provided for @mainMenu.
  ///
  /// In en, this message translates to:
  /// **'Main menu'**
  String get mainMenu;

  /// No description provided for @navRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get navRequests;

  /// No description provided for @navPhotoReports.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get navPhotoReports;

  /// No description provided for @roleDelegate.
  ///
  /// In en, this message translates to:
  /// **'Delegate'**
  String get roleDelegate;

  /// No description provided for @roleSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get roleSupervisor;

  /// No description provided for @roleCompanyAdmin.
  ///
  /// In en, this message translates to:
  /// **'Company admin'**
  String get roleCompanyAdmin;

  /// No description provided for @roleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super admin'**
  String get roleSuperAdmin;

  /// No description provided for @roleOrgAdmin.
  ///
  /// In en, this message translates to:
  /// **'Organization admin'**
  String get roleOrgAdmin;

  /// No description provided for @roleTechSupport.
  ///
  /// In en, this message translates to:
  /// **'Technical support'**
  String get roleTechSupport;

  /// No description provided for @roleMarketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get roleMarketing;

  /// No description provided for @roleHr.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get roleHr;

  /// No description provided for @defaultUserName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get defaultUserName;

  /// No description provided for @offlineBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineBannerTitle;

  /// No description provided for @offlineLastSync.
  ///
  /// In en, this message translates to:
  /// **'Last updated {time}'**
  String offlineLastSync(Object time);

  /// No description provided for @offlineNoSyncYet.
  ///
  /// In en, this message translates to:
  /// **'We\'ll update when you\'re back online'**
  String get offlineNoSyncYet;

  /// No description provided for @offlineNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications can\'t load while you\'re offline. Connect and try again.'**
  String get offlineNotifications;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. Check your connection and try again.'**
  String get refreshFailed;

  /// No description provided for @startPhotosCta.
  ///
  /// In en, this message translates to:
  /// **'Start photos'**
  String get startPhotosCta;

  /// No description provided for @switchOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get switchOn;

  /// No description provided for @switchOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get switchOff;

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new?'**
  String get whatsNewTitle;

  /// No description provided for @releaseVersionDate.
  ///
  /// In en, this message translates to:
  /// **'Version {version} – {date}'**
  String releaseVersionDate(Object version, Object date);

  /// No description provided for @feedbackTypeFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature request'**
  String get feedbackTypeFeature;

  /// No description provided for @feedbackTypeBug.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get feedbackTypeBug;

  /// No description provided for @feedbackTypeQuestion.
  ///
  /// In en, this message translates to:
  /// **'General question'**
  String get feedbackTypeQuestion;

  /// No description provided for @feedbackTypeImprovement.
  ///
  /// In en, this message translates to:
  /// **'Improvement'**
  String get feedbackTypeImprovement;

  /// No description provided for @feedbackTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get feedbackTypeOther;

  /// No description provided for @reqTitle.
  ///
  /// In en, this message translates to:
  /// **'My requests'**
  String get reqTitle;

  /// No description provided for @refreshAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshAction;

  /// No description provided for @newRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get newRequest;

  /// No description provided for @reqEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get reqEmptyAll;

  /// No description provided for @reqEmptyFilter.
  ///
  /// In en, this message translates to:
  /// **'No requests with this status'**
  String get reqEmptyFilter;

  /// No description provided for @reqEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"New request\" to send one to your supervisor'**
  String get reqEmptyHint;

  /// No description provided for @annualLeaveBalance.
  ///
  /// In en, this message translates to:
  /// **'Annual leave balance'**
  String get annualLeaveBalance;

  /// No description provided for @weeklyOffPlan.
  ///
  /// In en, this message translates to:
  /// **'Weekly day-off plan'**
  String get weeklyOffPlan;

  /// No description provided for @daysOffPerMonth.
  ///
  /// In en, this message translates to:
  /// **'4 days off/month'**
  String get daysOffPerMonth;

  /// No description provided for @weeklyDayOff.
  ///
  /// In en, this message translates to:
  /// **'Weekly day off'**
  String get weeklyDayOff;

  /// No description provided for @oneDayEvery7.
  ///
  /// In en, this message translates to:
  /// **'1 day every 7 days'**
  String get oneDayEvery7;

  /// No description provided for @hourlyPermission.
  ///
  /// In en, this message translates to:
  /// **'Hourly permission'**
  String get hourlyPermission;

  /// No description provided for @availableLabel.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get availableLabel;

  /// No description provided for @annualBalance21.
  ///
  /// In en, this message translates to:
  /// **'Annual balance: 21 days'**
  String get annualBalance21;

  /// No description provided for @onceActivated.
  ///
  /// In en, this message translates to:
  /// **'Once activated'**
  String get onceActivated;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @statusPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPendingReview;

  /// No description provided for @statusApprovedPl.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApprovedPl;

  /// No description provided for @statusRejectedPl.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejectedPl;

  /// No description provided for @leaveSick.
  ///
  /// In en, this message translates to:
  /// **'Sick leave'**
  String get leaveSick;

  /// No description provided for @leaveEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency leave'**
  String get leaveEmergency;

  /// No description provided for @excuseLate.
  ///
  /// In en, this message translates to:
  /// **'Late arrival'**
  String get excuseLate;

  /// No description provided for @excuseEarlyLeave.
  ///
  /// In en, this message translates to:
  /// **'Early leave'**
  String get excuseEarlyLeave;

  /// No description provided for @excuseAbsence.
  ///
  /// In en, this message translates to:
  /// **'Excused absence'**
  String get excuseAbsence;

  /// No description provided for @leaveUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid leave'**
  String get leaveUnpaid;

  /// No description provided for @leaveAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual leave'**
  String get leaveAnnual;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @previewAttachment.
  ///
  /// In en, this message translates to:
  /// **'Preview attachment'**
  String get previewAttachment;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequest;

  /// No description provided for @cancelRequestConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this request?'**
  String get cancelRequestConfirm;

  /// No description provided for @keepRequest.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keepRequest;

  /// No description provided for @yesCancel.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get yesCancel;

  /// No description provided for @requestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get requestCancelled;

  /// No description provided for @requestType.
  ///
  /// In en, this message translates to:
  /// **'Request type'**
  String get requestType;

  /// No description provided for @weeklyPlanAvailableInfo.
  ///
  /// In en, this message translates to:
  /// **'You can request: hourly permission, an excused absence, or unpaid leave.'**
  String get weeklyPlanAvailableInfo;

  /// No description provided for @remainingDays.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {count} days'**
  String remainingDays(int count);

  /// No description provided for @usedDays.
  ///
  /// In en, this message translates to:
  /// **'Used: {count} days'**
  String usedDays(int count);

  /// No description provided for @totalQuotaDays.
  ///
  /// In en, this message translates to:
  /// **'Total: {count} days'**
  String totalQuotaDays(int count);

  /// No description provided for @forYear.
  ///
  /// In en, this message translates to:
  /// **'For {year}'**
  String forYear(int year);

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonLabel(Object reason);

  /// No description provided for @rejectReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason: {reason}'**
  String rejectReasonLabel(Object reason);

  /// No description provided for @approvedBy.
  ///
  /// In en, this message translates to:
  /// **'Approved by {name}'**
  String approvedBy(Object name);

  /// No description provided for @homeSupervisorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your supervisors'**
  String get homeSupervisorsTitle;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, {firstName}'**
  String homeGreeting(Object firstName);

  /// No description provided for @roleFieldDelegate.
  ///
  /// In en, this message translates to:
  /// **'Field delegate'**
  String get roleFieldDelegate;

  /// No description provided for @roleFieldSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Field supervisor'**
  String get roleFieldSupervisor;

  /// No description provided for @homeCoreDuties.
  ///
  /// In en, this message translates to:
  /// **'Your core duties'**
  String get homeCoreDuties;

  /// No description provided for @homeDutyAttendance.
  ///
  /// In en, this message translates to:
  /// **'Check in and out from the branch location.'**
  String get homeDutyAttendance;

  /// No description provided for @homeDutyTasks.
  ///
  /// In en, this message translates to:
  /// **'Complete and track your daily tasks.'**
  String get homeDutyTasks;

  /// No description provided for @homeDutyPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photograph offers and brands in hypermarkets and branches.'**
  String get homeDutyPhotos;

  /// No description provided for @companySupervisor.
  ///
  /// In en, this message translates to:
  /// **'Company supervisor'**
  String get companySupervisor;

  /// No description provided for @supervisorOfCompany.
  ///
  /// In en, this message translates to:
  /// **'Supervisor · {companyName}'**
  String supervisorOfCompany(Object companyName);

  /// No description provided for @assignedCompanySupervisor.
  ///
  /// In en, this message translates to:
  /// **'Assigned company supervisor'**
  String get assignedCompanySupervisor;

  /// No description provided for @callAction.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callAction;

  /// No description provided for @offerPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Offer photos'**
  String get offerPhotosTitle;

  /// No description provided for @offerPhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Take and upload approved offer photos in the hypermarket'**
  String get offerPhotosSubtitle;

  /// No description provided for @homeAttendanceSummary.
  ///
  /// In en, this message translates to:
  /// **'Attendance – {monthName}'**
  String homeAttendanceSummary(Object monthName);

  /// No description provided for @detailsAction.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsAction;

  /// No description provided for @statAttended.
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get statAttended;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String daysCount(int count);

  /// No description provided for @statAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get statAbsent;

  /// No description provided for @statDaysOff.
  ///
  /// In en, this message translates to:
  /// **'Days off'**
  String get statDaysOff;

  /// No description provided for @leavesOfFour.
  ///
  /// In en, this message translates to:
  /// **'{count} of 4 days'**
  String leavesOfFour(Object count);

  /// No description provided for @workPolicyNote.
  ///
  /// In en, this message translates to:
  /// **'26 workdays/month • 4 days off not counted as absence'**
  String get workPolicyNote;

  /// No description provided for @chainGomlaMarket.
  ///
  /// In en, this message translates to:
  /// **'Gomla Market'**
  String get chainGomlaMarket;

  /// No description provided for @chainFathallaMarket.
  ///
  /// In en, this message translates to:
  /// **'Fathalla Market'**
  String get chainFathallaMarket;

  /// No description provided for @chainZahranMarket.
  ///
  /// In en, this message translates to:
  /// **'Zahran Market'**
  String get chainZahranMarket;

  /// No description provided for @recentBranchActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent branch activity'**
  String get recentBranchActivity;

  /// No description provided for @viewLog.
  ///
  /// In en, this message translates to:
  /// **'View log'**
  String get viewLog;

  /// No description provided for @unknownBranch.
  ///
  /// In en, this message translates to:
  /// **'Unknown branch'**
  String get unknownBranch;

  /// No description provided for @onShift.
  ///
  /// In en, this message translates to:
  /// **'On shift'**
  String get onShift;

  /// No description provided for @durationHm.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHm(Object hours, Object minutes);

  /// No description provided for @branchLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch: {cleanBranchName}'**
  String branchLabel(Object cleanBranchName);

  /// No description provided for @homeRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Submit and track leave and excuse requests'**
  String get homeRequestsSubtitle;

  /// No description provided for @companySupervisorWithName.
  ///
  /// In en, this message translates to:
  /// **'Company supervisor ({companyName})'**
  String companySupervisorWithName(Object companyName);

  /// No description provided for @errorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithMessage(Object error);

  /// No description provided for @noSupervisorForCompany.
  ///
  /// In en, this message translates to:
  /// **'No supervisor registered for this company yet\n(Company ID: {companyUID})'**
  String noSupervisorForCompany(Object companyUID);

  /// No description provided for @pendingCountBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String pendingCountBadge(Object count);

  /// No description provided for @orgMarketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get orgMarketing;

  /// No description provided for @orgAdminPanel.
  ///
  /// In en, this message translates to:
  /// **'Admin panel'**
  String get orgAdminPanel;

  /// No description provided for @orgAccounting.
  ///
  /// In en, this message translates to:
  /// **'Accounting'**
  String get orgAccounting;

  /// No description provided for @switchedToOrg.
  ///
  /// In en, this message translates to:
  /// **'Switched to {orgLabel}'**
  String switchedToOrg(Object orgLabel);

  /// No description provided for @unknownOrganization.
  ///
  /// In en, this message translates to:
  /// **'Unknown organization'**
  String get unknownOrganization;

  /// No description provided for @alreadyInOrg.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in this organization.'**
  String get alreadyInOrg;

  /// No description provided for @logoutAction.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutAction;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out?\nYour local data will be saved first.'**
  String get logoutConfirm;

  /// No description provided for @logoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t log out: {error}'**
  String logoutFailed(Object error);

  /// No description provided for @backAction.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backAction;

  /// No description provided for @sendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get sendFeedback;

  /// No description provided for @rateTheApp.
  ///
  /// In en, this message translates to:
  /// **'Rate the app'**
  String get rateTheApp;

  /// No description provided for @manageFeedback.
  ///
  /// In en, this message translates to:
  /// **'Manage feedback'**
  String get manageFeedback;

  /// No description provided for @myFeedback.
  ///
  /// In en, this message translates to:
  /// **'My feedback'**
  String get myFeedback;

  /// No description provided for @photoPermissions2.
  ///
  /// In en, this message translates to:
  /// **'Photo permissions'**
  String get photoPermissions2;

  /// No description provided for @appColor.
  ///
  /// In en, this message translates to:
  /// **'App color'**
  String get appColor;

  /// No description provided for @attCheckingZone.
  ///
  /// In en, this message translates to:
  /// **'Checking location…'**
  String get attCheckingZone;

  /// No description provided for @attVerifyingCoords.
  ///
  /// In en, this message translates to:
  /// **'Verifying your location and distance to the branch'**
  String get attVerifyingCoords;

  /// No description provided for @attInsideZone.
  ///
  /// In en, this message translates to:
  /// **'Inside work zone'**
  String get attInsideZone;

  /// No description provided for @attWithinBranchRange.
  ///
  /// In en, this message translates to:
  /// **'Within range of {branch}'**
  String attWithinBranchRange(Object branch);

  /// No description provided for @attWithinAllowedRange.
  ///
  /// In en, this message translates to:
  /// **'Within allowed range'**
  String get attWithinAllowedRange;

  /// No description provided for @attOutsideZone.
  ///
  /// In en, this message translates to:
  /// **'Outside work zone'**
  String get attOutsideZone;

  /// No description provided for @attMoveCloserTo.
  ///
  /// In en, this message translates to:
  /// **'Move closer to {branch} to check in'**
  String attMoveCloserTo(Object branch);

  /// No description provided for @attOutsideApprovedBranches.
  ///
  /// In en, this message translates to:
  /// **'Outside approved branches'**
  String get attOutsideApprovedBranches;

  /// No description provided for @distanceKmM.
  ///
  /// In en, this message translates to:
  /// **'{km} km ({meters} m)'**
  String distanceKmM(Object km, Object meters);

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @currentMonth.
  ///
  /// In en, this message translates to:
  /// **'Current month'**
  String get currentMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @attWorkPolicyNote.
  ///
  /// In en, this message translates to:
  /// **'26 workdays • 4 days off not counted as absence'**
  String get attWorkPolicyNote;

  /// No description provided for @distanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance: {formattedDistance}'**
  String distanceLabel(Object formattedDistance);

  /// No description provided for @radiusLabel.
  ///
  /// In en, this message translates to:
  /// **'Radius: {allowedRadius} m'**
  String radiusLabel(Object allowedRadius);

  /// No description provided for @recheckLocation.
  ///
  /// In en, this message translates to:
  /// **'Recheck location'**
  String get recheckLocation;

  /// No description provided for @activeChain.
  ///
  /// In en, this message translates to:
  /// **'Current chain'**
  String get activeChain;

  /// No description provided for @allChains.
  ///
  /// In en, this message translates to:
  /// **'All chains'**
  String get allChains;

  /// No description provided for @attNoSessionsInChain.
  ///
  /// In en, this message translates to:
  /// **'No attendance records for {chain} this month'**
  String attNoSessionsInChain(Object chain);

  /// No description provided for @attDaysInOtherChains.
  ///
  /// In en, this message translates to:
  /// **'You have {count} attended days in other chains.'**
  String attDaysInOtherChains(Object count);

  /// No description provided for @showAllChains.
  ///
  /// In en, this message translates to:
  /// **'Show all chains'**
  String get showAllChains;

  /// No description provided for @attAutoClosedNote.
  ///
  /// In en, this message translates to:
  /// **'Checked out automatically 9 hours after the shift started, since no check-out was recorded'**
  String get attAutoClosedNote;

  /// No description provided for @autoClosed9h.
  ///
  /// In en, this message translates to:
  /// **'Auto-closed (9h)'**
  String get autoClosed9h;

  /// No description provided for @checkOut2.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get checkOut2;

  /// No description provided for @attCheckingLocation.
  ///
  /// In en, this message translates to:
  /// **'Checking location…'**
  String get attCheckingLocation;

  /// No description provided for @checkIn2.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkIn2;

  /// No description provided for @noBranchesForOrgYet.
  ///
  /// In en, this message translates to:
  /// **'No branches registered for this organization yet.'**
  String get noBranchesForOrgYet;

  /// No description provided for @noBranchesForOrg.
  ///
  /// In en, this message translates to:
  /// **'No branches registered for this organization.'**
  String get noBranchesForOrg;

  /// No description provided for @attYouAreWithinBranch.
  ///
  /// In en, this message translates to:
  /// **'You are within range of {branch}'**
  String attYouAreWithinBranch(Object branch);

  /// No description provided for @attMoveCloser.
  ///
  /// In en, this message translates to:
  /// **'Move closer to the branch to check in'**
  String get attMoveCloser;

  /// No description provided for @attOutsideApproved.
  ///
  /// In en, this message translates to:
  /// **'You are outside approved branches'**
  String get attOutsideApproved;

  /// No description provided for @attCheckInSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Check-in saved on this device. It will sync when you are back online.'**
  String get attCheckInSavedOffline;

  /// No description provided for @attCheckOutSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Check-out saved on this device. It will sync when you are back online.'**
  String get attCheckOutSavedOffline;

  /// No description provided for @syncDone.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncDone;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncFailed;

  /// No description provided for @attDelegateOfCompany.
  ///
  /// In en, this message translates to:
  /// **'Delegate · {companyName}'**
  String attDelegateOfCompany(Object companyName);

  /// No description provided for @attendanceLog.
  ///
  /// In en, this message translates to:
  /// **'Attendance log'**
  String get attendanceLog;

  /// No description provided for @distanceMeters.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String distanceMeters(Object meters);

  /// No description provided for @attLocatingYou.
  ///
  /// In en, this message translates to:
  /// **'Finding your location and checking branches…'**
  String get attLocatingYou;

  /// No description provided for @attLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Turn on GPS.'**
  String get attLocationUnavailable;

  /// No description provided for @attInsideBranchWithDistance.
  ///
  /// In en, this message translates to:
  /// **'You are within range of {branch} ({meters} m)'**
  String attInsideBranchWithDistance(Object branch, Object meters);

  /// No description provided for @attOutsideBranchWithRadius.
  ///
  /// In en, this message translates to:
  /// **'You are outside the branch range ({meters} m). Allowed range: {radius} m.'**
  String attOutsideBranchWithRadius(Object meters, Object radius);

  /// No description provided for @attEnsureGps.
  ///
  /// In en, this message translates to:
  /// **'Make sure GPS is on and wait for your location.'**
  String get attEnsureGps;

  /// No description provided for @metersValue.
  ///
  /// In en, this message translates to:
  /// **'{value} m'**
  String metersValue(Object value);

  /// No description provided for @attCannotActOutside.
  ///
  /// In en, this message translates to:
  /// **'You can\'t {action} while outside the branch ({distance}). Please be inside the branch.'**
  String attCannotActOutside(Object action, Object distance);

  /// No description provided for @attCheckingInAt.
  ///
  /// In en, this message translates to:
  /// **'Checking in at {branchName}…'**
  String attCheckingInAt(Object branchName);

  /// No description provided for @locationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Location services are off. Turn them on.'**
  String get locationServicesOff;

  /// No description provided for @locationPermissionDenied2.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied'**
  String get locationPermissionDenied2;

  /// No description provided for @locationPermissionDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Location permission is permanently denied.'**
  String get locationPermissionDeniedForever;

  /// No description provided for @fakeGpsDetected.
  ///
  /// In en, this message translates to:
  /// **'A fake GPS app was detected. Turn it off to check in and out.'**
  String get fakeGpsDetected;

  /// No description provided for @locationTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out getting your location. Make sure GPS is on and you\'re in an open area.'**
  String get locationTimeout;

  /// No description provided for @locationError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while getting your location.'**
  String get locationError;

  /// No description provided for @trustedTime.
  ///
  /// In en, this message translates to:
  /// **'Trusted time'**
  String get trustedTime;

  /// No description provided for @attActionCheckIn.
  ///
  /// In en, this message translates to:
  /// **'check in'**
  String get attActionCheckIn;

  /// No description provided for @attActionCheckOut.
  ///
  /// In en, this message translates to:
  /// **'check out'**
  String get attActionCheckOut;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @accountNotIdentified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t identify the account'**
  String get accountNotIdentified;

  /// No description provided for @profilePhotoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated'**
  String get profilePhotoUpdated;

  /// No description provided for @photoUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the photo: {error}'**
  String photoUploadFailed(Object error);

  /// No description provided for @profilePhotoDeleted.
  ///
  /// In en, this message translates to:
  /// **'Profile photo removed'**
  String get profilePhotoDeleted;

  /// No description provided for @photoDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the photo: {error}'**
  String photoDeleteFailed(Object error);

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @takePhotoCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhotoCamera;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @removeCurrentPhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove current photo'**
  String get removeCurrentPhoto;

  /// No description provided for @roleSuperAdmin2.
  ///
  /// In en, this message translates to:
  /// **'Super admin'**
  String get roleSuperAdmin2;

  /// No description provided for @roleTechSupport2.
  ///
  /// In en, this message translates to:
  /// **'Technical support'**
  String get roleTechSupport2;

  /// No description provided for @roleOrgAdmin2.
  ///
  /// In en, this message translates to:
  /// **'Organization admin'**
  String get roleOrgAdmin2;

  /// No description provided for @roleCompanyAdmin2.
  ///
  /// In en, this message translates to:
  /// **'Company admin'**
  String get roleCompanyAdmin2;

  /// No description provided for @roleHrOfficer.
  ///
  /// In en, this message translates to:
  /// **'HR officer'**
  String get roleHrOfficer;

  /// No description provided for @roleAccountant.
  ///
  /// In en, this message translates to:
  /// **'Accounting'**
  String get roleAccountant;

  /// No description provided for @roleMarketing2.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get roleMarketing2;

  /// No description provided for @personalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal information'**
  String get personalInfo;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @editField.
  ///
  /// In en, this message translates to:
  /// **'Edit {label}'**
  String editField(Object label);

  /// No description provided for @nameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get nameUpdated;

  /// No description provided for @emailUpdated.
  ///
  /// In en, this message translates to:
  /// **'Email updated'**
  String get emailUpdated;

  /// No description provided for @phoneUpdated.
  ///
  /// In en, this message translates to:
  /// **'Phone number updated'**
  String get phoneUpdated;

  /// No description provided for @editName2.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get editName2;

  /// No description provided for @editEmail.
  ///
  /// In en, this message translates to:
  /// **'Edit email'**
  String get editEmail;

  /// No description provided for @editPhone.
  ///
  /// In en, this message translates to:
  /// **'Edit phone number'**
  String get editPhone;

  /// No description provided for @fullName2.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName2;

  /// No description provided for @newEmail.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get newEmail;

  /// No description provided for @newPhone.
  ///
  /// In en, this message translates to:
  /// **'New phone number'**
  String get newPhone;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterName;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterEmail;

  /// No description provided for @enterPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterPhone;

  /// No description provided for @nameMin3.
  ///
  /// In en, this message translates to:
  /// **'Name must be at least 3 characters'**
  String get nameMin3;

  /// No description provided for @invalidEmail2.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get invalidEmail2;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get invalidPhone;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @enterCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password'**
  String get enterCurrentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @enterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a new password'**
  String get enterNewPassword;

  /// No description provided for @passwordMin6.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordMin6;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @enterConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm your password'**
  String get enterConfirmPassword;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get passwordsDontMatch;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
