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
  /// **'Log out'**
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
  /// **'This account is pending or suspended. Please contact Tashil management.'**
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
  /// **'Scan the QR code in the marketing office.'**
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
  /// **'No attendance records'**
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
  /// **'Location access denied'**
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
  /// **'Dark mode'**
  String get darkMode;

  /// Privacy policy setting label
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
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

  /// Version label in web settings (no mobile app name)
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String webVersion(String version);

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
  /// **'In progress'**
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
  /// **'Tap “New request” to send one to your supervisor'**
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
  /// **'Annual: 21 days'**
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
  String leavesOfFour(int count);

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
  /// **'Recent activity'**
  String get recentBranchActivity;

  /// No description provided for @viewLog.
  ///
  /// In en, this message translates to:
  /// **'View history'**
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
  /// **'No supervisor registered for this company yet'**
  String get noSupervisorForCompany;

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
  /// **'Administration'**
  String get orgAdminPanel;

  /// No description provided for @orgAccounting.
  ///
  /// In en, this message translates to:
  /// **'Finance & accounting'**
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
  /// **'Checking your location…'**
  String get attVerifyingCoords;

  /// No description provided for @attInsideZone.
  ///
  /// In en, this message translates to:
  /// **'You\'re in the work zone'**
  String get attInsideZone;

  /// No description provided for @attWithinBranchRange.
  ///
  /// In en, this message translates to:
  /// **'Within range of {branch}'**
  String attWithinBranchRange(Object branch);

  /// No description provided for @attOutsideZone.
  ///
  /// In en, this message translates to:
  /// **'You\'re outside the work zone'**
  String get attOutsideZone;

  /// No description provided for @attMoveCloserTo.
  ///
  /// In en, this message translates to:
  /// **'Move closer to {branch} to check in'**
  String attMoveCloserTo(Object branch);

  /// No description provided for @attOutsideApprovedBranches.
  ///
  /// In en, this message translates to:
  /// **'You\'re not at an approved branch'**
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
  /// **'Allowed radius: {allowedRadius} m'**
  String radiusLabel(Object allowedRadius);

  /// No description provided for @recheckLocation.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
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

  /// No description provided for @attAutoClosedNote.
  ///
  /// In en, this message translates to:
  /// **'Checked out automatically 11.5 hours after the shift started, since no check-out was recorded'**
  String get attAutoClosedNote;

  /// No description provided for @autoClosedAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto-closed (11.5h)'**
  String get autoClosedAuto;

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

  /// No description provided for @noBranchesForOrg.
  ///
  /// In en, this message translates to:
  /// **'No branches for this organization yet'**
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
  /// **'Couldn\'t sync'**
  String get syncFailed;

  /// No description provided for @attDelegateOfCompany.
  ///
  /// In en, this message translates to:
  /// **'Delegate · {companyName}'**
  String attDelegateOfCompany(Object companyName);

  /// No description provided for @attendanceLog.
  ///
  /// In en, this message translates to:
  /// **'Attendance history'**
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

  /// No description provided for @attLocatingShort.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get attLocatingShort;

  /// No description provided for @attEarlyCheckOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Check out already?'**
  String get attEarlyCheckOutTitle;

  /// No description provided for @attEarlyCheckOutBody.
  ///
  /// In en, this message translates to:
  /// **'You checked in {minutes} min ago. Checking out now will close this attendance.'**
  String attEarlyCheckOutBody(int minutes);

  /// No description provided for @attEarlyCheckOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Yes, check out'**
  String get attEarlyCheckOutConfirm;

  /// No description provided for @attEarlyCheckOutCancel.
  ///
  /// In en, this message translates to:
  /// **'Stay checked in'**
  String get attEarlyCheckOutCancel;

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

  /// No description provided for @attCannotActOutside.
  ///
  /// In en, this message translates to:
  /// **'You can\'t {action} while outside the branch ({distance}). Please be inside the branch.'**
  String attCannotActOutside(Object action, Object distance);

  /// No description provided for @attCannotActOutsideNoDistance.
  ///
  /// In en, this message translates to:
  /// **'You can\'t {action} while outside the branch. Please be inside the branch.'**
  String attCannotActOutsideNoDistance(Object action);

  /// No description provided for @attCannotActOutsideAtBranch.
  ///
  /// In en, this message translates to:
  /// **'You can\'t {action} while outside {branch} ({distance}). Please be inside the branch.'**
  String attCannotActOutsideAtBranch(
    Object action,
    Object branch,
    Object distance,
  );

  /// No description provided for @attCannotActOutsideBranchOnly.
  ///
  /// In en, this message translates to:
  /// **'You can\'t {action} while outside {branch}. Please be inside the branch.'**
  String attCannotActOutsideBranchOnly(Object action, Object branch);

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
  /// **'Location access is off. Turn it on in Settings.'**
  String get locationPermissionDeniedForever;

  /// No description provided for @fakeGpsDetected.
  ///
  /// In en, this message translates to:
  /// **'A fake GPS app was detected. Turn it off to check in or out.'**
  String get fakeGpsDetected;

  /// No description provided for @locationTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out getting your location. Make sure GPS is on and you\'re in an open area.'**
  String get locationTimeout;

  /// No description provided for @locationError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Try again.'**
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
  /// **'Profile photo deleted'**
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
  /// **'Delete photo'**
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

  /// No description provided for @refreshPolicy.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshPolicy;

  /// No description provided for @allPolicyItems.
  ///
  /// In en, this message translates to:
  /// **'All items ({count})'**
  String allPolicyItems(Object count);

  /// No description provided for @penPolicyCardBody.
  ///
  /// In en, this message translates to:
  /// **'The deduction for each violation, first time and when repeated.'**
  String get penPolicyCardBody;

  /// No description provided for @searchPolicy.
  ///
  /// In en, this message translates to:
  /// **'Search the policy'**
  String get searchPolicy;

  /// No description provided for @allWithCount.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String allWithCount(Object count);

  /// No description provided for @adminRestricted.
  ///
  /// In en, this message translates to:
  /// **'Admin only'**
  String get adminRestricted;

  /// No description provided for @firstTime.
  ///
  /// In en, this message translates to:
  /// **'First time'**
  String get firstTime;

  /// No description provided for @amountEgp.
  ///
  /// In en, this message translates to:
  /// **'{amount} EGP'**
  String amountEgp(Object amount);

  /// No description provided for @whenRepeated.
  ///
  /// In en, this message translates to:
  /// **'When repeated'**
  String get whenRepeated;

  /// No description provided for @perManagementDecision.
  ///
  /// In en, this message translates to:
  /// **'Per management decision'**
  String get perManagementDecision;

  /// No description provided for @plannedAction.
  ///
  /// In en, this message translates to:
  /// **'Action: {action}'**
  String plannedAction(Object action);

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @tryOtherSearch.
  ///
  /// In en, this message translates to:
  /// **'Try other words or a different category.'**
  String get tryOtherSearch;

  /// No description provided for @noViolationDocs.
  ///
  /// In en, this message translates to:
  /// **'No attachments'**
  String get noViolationDocs;

  /// No description provided for @violationReceipt.
  ///
  /// In en, this message translates to:
  /// **'Violation document'**
  String get violationReceipt;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load image'**
  String get imageLoadFailed;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @attachedDocuments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachedDocuments;

  /// No description provided for @receiptNumber.
  ///
  /// In en, this message translates to:
  /// **'Document {number}'**
  String receiptNumber(Object number);

  /// No description provided for @photoReceipt.
  ///
  /// In en, this message translates to:
  /// **'Document photo'**
  String get photoReceipt;

  /// No description provided for @tapToPreview.
  ///
  /// In en, this message translates to:
  /// **'Tap to preview'**
  String get tapToPreview;

  /// No description provided for @tapToOpen.
  ///
  /// In en, this message translates to:
  /// **'Tap to open'**
  String get tapToOpen;

  /// No description provided for @deleteAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'Delete all notifications'**
  String get deleteAllNotifications;

  /// No description provided for @deleteAllNotificationsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all notifications from your list?\n(They won\'t appear in your account again but stay in the system log.)'**
  String get deleteAllNotificationsConfirm;

  /// No description provided for @allNotificationsDeleted.
  ///
  /// In en, this message translates to:
  /// **'All notifications deleted from your list'**
  String get allNotificationsDeleted;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @sendNewNotification.
  ///
  /// In en, this message translates to:
  /// **'Send notification'**
  String get sendNewNotification;

  /// No description provided for @deleteNotification.
  ///
  /// In en, this message translates to:
  /// **'Delete notification'**
  String get deleteNotification;

  /// No description provided for @deleteNotificationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this notification from your list?\n(It stays in the system log.)'**
  String get deleteNotificationConfirm;

  /// No description provided for @notificationDeleted.
  ///
  /// In en, this message translates to:
  /// **'Notification deleted'**
  String get notificationDeleted;

  /// No description provided for @systemAdministration.
  ///
  /// In en, this message translates to:
  /// **'System administration'**
  String get systemAdministration;

  /// No description provided for @senderLine.
  ///
  /// In en, this message translates to:
  /// **'From: {name} ({role})'**
  String senderLine(Object name, Object role);

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @viewTask.
  ///
  /// In en, this message translates to:
  /// **'View task'**
  String get viewTask;

  /// No description provided for @updateAppNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateAppNow;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @taskCompletedConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Task marked as completed'**
  String get taskCompletedConfirmed;

  /// No description provided for @taskStarted.
  ///
  /// In en, this message translates to:
  /// **'Task started'**
  String get taskStarted;

  /// No description provided for @noTasksNow.
  ///
  /// In en, this message translates to:
  /// **'No tasks right now'**
  String get noTasksNow;

  /// No description provided for @tasksAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Tasks will appear here as soon as they are assigned to you.'**
  String get tasksAppearHere;

  /// No description provided for @taskDeleted.
  ///
  /// In en, this message translates to:
  /// **'Task deleted'**
  String get taskDeleted;

  /// No description provided for @taskDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the task: {error}'**
  String taskDeleteFailed(Object error);

  /// No description provided for @timeAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String timeAgoDays(int count);

  /// No description provided for @timeAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String timeAgoHours(int count);

  /// No description provided for @timeAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String timeAgoMinutes(int count);

  /// No description provided for @confirmDeletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get confirmDeletePhoto;

  /// No description provided for @deletePhotoFromConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this photo sent by \"{delegateName}\" at \"{branch}\"?'**
  String deletePhotoFromConfirm(Object delegateName, Object branch);

  /// No description provided for @photoDeletePermanentNote.
  ///
  /// In en, this message translates to:
  /// **'The photo will be permanently deleted from the database and storage.'**
  String get photoDeletePermanentNote;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @chooseMonth.
  ///
  /// In en, this message translates to:
  /// **'Choose month'**
  String get chooseMonth;

  /// No description provided for @photosCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No photos} =1{1 photo} other{{count} photos}}'**
  String photosCount(int count);

  /// No description provided for @photoReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo reports'**
  String get photoReportsTitle;

  /// No description provided for @refreshPhotos.
  ///
  /// In en, this message translates to:
  /// **'Refresh photos'**
  String get refreshPhotos;

  /// No description provided for @photosArchiveNote.
  ///
  /// In en, this message translates to:
  /// **'Photos are stored in the company archive, separate from delegate accounts'**
  String get photosArchiveNote;

  /// No description provided for @totalPhotos.
  ///
  /// In en, this message translates to:
  /// **'Total photos'**
  String get totalPhotos;

  /// No description provided for @branchesVisited.
  ///
  /// In en, this message translates to:
  /// **'Branches visited'**
  String get branchesVisited;

  /// No description provided for @activeDelegates.
  ///
  /// In en, this message translates to:
  /// **'Active delegates'**
  String get activeDelegates;

  /// No description provided for @byDate.
  ///
  /// In en, this message translates to:
  /// **'By date'**
  String get byDate;

  /// No description provided for @byBranch.
  ///
  /// In en, this message translates to:
  /// **'By branch'**
  String get byBranch;

  /// No description provided for @byDelegate.
  ///
  /// In en, this message translates to:
  /// **'By delegate'**
  String get byDelegate;

  /// No description provided for @photoReportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load photo reports'**
  String get photoReportsLoadFailed;

  /// No description provided for @unknownDelegate.
  ///
  /// In en, this message translates to:
  /// **'Unknown delegate'**
  String get unknownDelegate;

  /// No description provided for @pendingOnPhone.
  ///
  /// In en, this message translates to:
  /// **'On phone'**
  String get pendingOnPhone;

  /// No description provided for @uploadedToServer.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploadedToServer;

  /// No description provided for @noPhotosInMonth.
  ///
  /// In en, this message translates to:
  /// **'No photos in {month}'**
  String noPhotosInMonth(Object month);

  /// No description provided for @useArrowsForMonths.
  ///
  /// In en, this message translates to:
  /// **'Use the arrows above to view earlier months.'**
  String get useArrowsForMonths;

  /// No description provided for @photoDetails.
  ///
  /// In en, this message translates to:
  /// **'Photo details'**
  String get photoDetails;

  /// No description provided for @deletePhotoPermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete photo permanently'**
  String get deletePhotoPermanently;

  /// No description provided for @pinchToZoom.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom in'**
  String get pinchToZoom;

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get deletePhoto;

  /// No description provided for @photoSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo saved to your gallery.'**
  String get photoSavedToGallery;

  /// No description provided for @grantPhotosPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow photo access in your phone settings.'**
  String get grantPhotosPermission;

  /// No description provided for @photoSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the photo: {error}'**
  String photoSaveFailed(Object error);

  /// No description provided for @savingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Saving photo…'**
  String get savingPhoto;

  /// No description provided for @savedToPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved to phone'**
  String get savedToPhone;

  /// No description provided for @savePhoto.
  ///
  /// In en, this message translates to:
  /// **'Save photo'**
  String get savePhoto;

  /// No description provided for @branchField.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get branchField;

  /// No description provided for @capturedAtField.
  ///
  /// In en, this message translates to:
  /// **'Captured at'**
  String get capturedAtField;

  /// No description provided for @delegateField.
  ///
  /// In en, this message translates to:
  /// **'Delegate'**
  String get delegateField;

  /// No description provided for @delegateCommentField.
  ///
  /// In en, this message translates to:
  /// **'Delegate\'s comment'**
  String get delegateCommentField;

  /// No description provided for @cameraOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the camera: {error}'**
  String cameraOpenFailed(Object error);

  /// No description provided for @photoRemovedFromSession.
  ///
  /// In en, this message translates to:
  /// **'Photo deleted'**
  String get photoRemovedFromSession;

  /// No description provided for @offerPhotosSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Offer photos (supervisor)'**
  String get offerPhotosSupervisor;

  /// No description provided for @photosSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'{count} photos saved on this device. They will upload automatically when you are back online.'**
  String photosSavedOffline(Object count);

  /// No description provided for @photosUploaded.
  ///
  /// In en, this message translates to:
  /// **'{count} photos uploaded and the report saved.'**
  String photosUploaded(Object count);

  /// No description provided for @photoSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Photo saved on this device. It will upload automatically when you are back online.'**
  String get photoSavedOffline;

  /// No description provided for @photoUploaded.
  ///
  /// In en, this message translates to:
  /// **'Photo uploaded and the report saved.'**
  String get photoUploaded;

  /// No description provided for @loadingPhotoPermissions.
  ///
  /// In en, this message translates to:
  /// **'Loading photo permissions…'**
  String get loadingPhotoPermissions;

  /// No description provided for @choosePhotoPermission.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo permission *'**
  String get choosePhotoPermission;

  /// No description provided for @permissionOption.
  ///
  /// In en, this message translates to:
  /// **'{companyName}{dept} - {length} branches'**
  String permissionOption(Object companyName, Object dept, Object length);

  /// No description provided for @branchWithId.
  ///
  /// In en, this message translates to:
  /// **'Branch {id}'**
  String branchWithId(Object id);

  /// No description provided for @offerPhotoPermissionOf.
  ///
  /// In en, this message translates to:
  /// **'Photo permission: {companyName}'**
  String offerPhotoPermissionOf(Object companyName);

  /// No description provided for @companyLabel2.
  ///
  /// In en, this message translates to:
  /// **'Company: {companyName}'**
  String companyLabel2(Object companyName);

  /// No description provided for @departmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Department: {department}'**
  String departmentLabel(Object department);

  /// No description provided for @noBranchesInPermissionFor.
  ///
  /// In en, this message translates to:
  /// **'No branches are registered for ({organizationName}) in this permission.'**
  String noBranchesInPermissionFor(Object organizationName);

  /// No description provided for @noBranchesInPermission.
  ///
  /// In en, this message translates to:
  /// **'No branches are set for this permission yet. Ask your supervisor to add them.'**
  String get noBranchesInPermission;

  /// No description provided for @chooseBranchOf.
  ///
  /// In en, this message translates to:
  /// **'Select branch ({organizationName}) *'**
  String chooseBranchOf(Object organizationName);

  /// No description provided for @chooseBranchRequired.
  ///
  /// In en, this message translates to:
  /// **'Select branch *'**
  String get chooseBranchRequired;

  /// No description provided for @takeOfferPhotos.
  ///
  /// In en, this message translates to:
  /// **'Take offer photos'**
  String get takeOfferPhotos;

  /// No description provided for @multiPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'You can take several photos of this branch\'s products and stands at once'**
  String get multiPhotoHint;

  /// No description provided for @takeFirstPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take first photo'**
  String get takeFirstPhoto;

  /// No description provided for @visitGallery.
  ///
  /// In en, this message translates to:
  /// **'Visit photos'**
  String get visitGallery;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @photoNumber.
  ///
  /// In en, this message translates to:
  /// **'Photo {number}'**
  String photoNumber(Object number);

  /// No description provided for @retakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Retake this photo'**
  String get retakePhoto;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @visitNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Visit notes ({count} photos) (optional)'**
  String visitNotesLabel(Object count);

  /// No description provided for @visitNotesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Products displayed, shelf arranged and prices clearly visible…'**
  String get visitNotesHint;

  /// No description provided for @uploadingPhotoXofY.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo {current} of {total}…'**
  String uploadingPhotoXofY(Object current, Object total);

  /// No description provided for @uploadingPhotosReport.
  ///
  /// In en, this message translates to:
  /// **'Uploading photos and saving the report…'**
  String get uploadingPhotosReport;

  /// No description provided for @nameCompanySupervisor.
  ///
  /// In en, this message translates to:
  /// **'{fullName} (company supervisor)'**
  String nameCompanySupervisor(Object fullName);

  /// No description provided for @chooseBranchFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a branch first.'**
  String get chooseBranchFirst;

  /// No description provided for @takeAtLeastOnePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take at least one photo before saving.'**
  String get takeAtLeastOnePhoto;

  /// No description provided for @submitReportCount.
  ///
  /// In en, this message translates to:
  /// **'Submit report ({count} photos)'**
  String submitReportCount(Object count);

  /// No description provided for @chooseBranchToStart.
  ///
  /// In en, this message translates to:
  /// **'Choose a branch to start taking photos'**
  String get chooseBranchToStart;

  /// No description provided for @chooseBranchHint.
  ///
  /// In en, this message translates to:
  /// **'Select the branch you are in from the list above to enable the camera button.'**
  String get chooseBranchHint;

  /// No description provided for @noPhotoPermissions.
  ///
  /// In en, this message translates to:
  /// **'No photo permissions right now'**
  String get noPhotoPermissions;

  /// No description provided for @askSupervisorForPermission.
  ///
  /// In en, this message translates to:
  /// **'Ask your supervisor for a photo permission.'**
  String get askSupervisorForPermission;

  /// No description provided for @photoReportsOf.
  ///
  /// In en, this message translates to:
  /// **'Photo reports: {companyName}'**
  String photoReportsOf(Object companyName);

  /// No description provided for @loadingPhotoReports.
  ///
  /// In en, this message translates to:
  /// **'Loading photo reports…'**
  String get loadingPhotoReports;

  /// No description provided for @noUploadedPhotos.
  ///
  /// In en, this message translates to:
  /// **'No uploaded photos yet'**
  String get noUploadedPhotos;

  /// No description provided for @filterByBranch.
  ///
  /// In en, this message translates to:
  /// **'Filter by branch'**
  String get filterByBranch;

  /// No description provided for @allBranches.
  ///
  /// In en, this message translates to:
  /// **'All branches'**
  String get allBranches;

  /// No description provided for @filterByDelegate.
  ///
  /// In en, this message translates to:
  /// **'Filter by delegate'**
  String get filterByDelegate;

  /// No description provided for @allDelegates2.
  ///
  /// In en, this message translates to:
  /// **'All delegates'**
  String get allDelegates2;

  /// No description provided for @shownResults.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String shownResults(Object shown, Object total);

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @noComment.
  ///
  /// In en, this message translates to:
  /// **'No comment'**
  String get noComment;

  /// No description provided for @showMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'Show more ({count} more photos)'**
  String showMorePhotos(Object count);

  /// No description provided for @loadingPhotosReports.
  ///
  /// In en, this message translates to:
  /// **'Loading photos and reports…'**
  String get loadingPhotosReports;

  /// No description provided for @syncingPhotosXofY.
  ///
  /// In en, this message translates to:
  /// **'Uploading photos ({synced} of {total})…'**
  String syncingPhotosXofY(Object synced, Object total);

  /// No description provided for @syncingRemainingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Uploading remaining photos…'**
  String get syncingRemainingPhotos;

  /// No description provided for @photosSavedOnPhone.
  ///
  /// In en, this message translates to:
  /// **'{count} photos saved on the phone'**
  String photosSavedOnPhone(Object count);

  /// No description provided for @waitingToUpload.
  ///
  /// In en, this message translates to:
  /// **'Will upload when you are online'**
  String get waitingToUpload;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @noFeedbackYet.
  ///
  /// In en, this message translates to:
  /// **'No feedback yet'**
  String get noFeedbackYet;

  /// No description provided for @sendFirstFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send your first feedback'**
  String get sendFirstFeedback;

  /// No description provided for @adminResponse.
  ///
  /// In en, this message translates to:
  /// **'Admin response'**
  String get adminResponse;

  /// No description provided for @feedbackIntro.
  ///
  /// In en, this message translates to:
  /// **'Your opinion matters. Help us improve the app'**
  String get feedbackIntro;

  /// No description provided for @feedbackType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get feedbackType;

  /// No description provided for @yourMessage.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get yourMessage;

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Write your feedback'**
  String get feedbackHint;

  /// No description provided for @enterMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter your message'**
  String get enterMessage;

  /// No description provided for @messageTooShort.
  ///
  /// In en, this message translates to:
  /// **'Message is too short (at least 10 characters)'**
  String get messageTooShort;

  /// No description provided for @screenshotOptional.
  ///
  /// In en, this message translates to:
  /// **'Screenshot (optional)'**
  String get screenshotOptional;

  /// No description provided for @chooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get chooseImage;

  /// No description provided for @sendAction.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendAction;

  /// No description provided for @thankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get thankYou;

  /// No description provided for @feedbackReceived.
  ///
  /// In en, this message translates to:
  /// **'We\'ve received your feedback and will review it soon.'**
  String get feedbackReceived;

  /// No description provided for @okAction.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okAction;

  /// No description provided for @loginSubtitleStaff.
  ///
  /// In en, this message translates to:
  /// **'Choose your account type and sign in'**
  String get loginSubtitleStaff;

  /// No description provided for @loginSubtitleDelegate.
  ///
  /// In en, this message translates to:
  /// **'Choose your account type and enter your details'**
  String get loginSubtitleDelegate;

  /// No description provided for @staffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffLabel;

  /// No description provided for @forgotPasswordQ.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordQ;

  /// No description provided for @phoneHelper.
  ///
  /// In en, this message translates to:
  /// **'The phone number registered with your company'**
  String get phoneHelper;

  /// No description provided for @nationalIdHelper.
  ///
  /// In en, this message translates to:
  /// **'14 digits'**
  String get nationalIdHelper;

  /// No description provided for @showAction.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showAction;

  /// No description provided for @hideAction.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideAction;

  /// No description provided for @enterPassword2.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPassword2;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get contactSupport;

  /// No description provided for @checkHighlightedFields.
  ///
  /// In en, this message translates to:
  /// **'Check the highlighted fields'**
  String get checkHighlightedFields;

  /// No description provided for @resetLinkSentIfRegistered.
  ///
  /// In en, this message translates to:
  /// **'If this email is registered, a reset link is on its way.'**
  String get resetLinkSentIfRegistered;

  /// No description provided for @resetLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the reset link. Try again.'**
  String get resetLinkFailed;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPassword;

  /// No description provided for @sendLink.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get sendLink;

  /// No description provided for @selectOrganization.
  ///
  /// In en, this message translates to:
  /// **'Select organization'**
  String get selectOrganization;

  /// No description provided for @multipleOrgsChoose.
  ///
  /// In en, this message translates to:
  /// **'You\'re registered in more than one organization. Choose one to continue.'**
  String get multipleOrgsChoose;

  /// No description provided for @weeklyPlanNote.
  ///
  /// In en, this message translates to:
  /// **'You get one day off a week (4 a month). Annual leave becomes available once your supervisor approves it.'**
  String get weeklyPlanNote;

  /// No description provided for @dateWithHours.
  ///
  /// In en, this message translates to:
  /// **'{date} • ({hours}h)'**
  String dateWithHours(Object date, Object hours);

  /// No description provided for @hoursCount.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String hoursCount(Object count);

  /// No description provided for @cancelRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the request: {error}'**
  String cancelRequestFailed(Object error);

  /// No description provided for @requestAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get requestAttachment;

  /// No description provided for @attachmentLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the attachment image'**
  String get attachmentLoadFailed;

  /// No description provided for @annualLeaveFromBalance.
  ///
  /// In en, this message translates to:
  /// **'Annual leave (from annual balance)'**
  String get annualLeaveFromBalance;

  /// No description provided for @annualLeaveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Annual leave (not available yet)'**
  String get annualLeaveUnavailable;

  /// No description provided for @lateArrivalHourly.
  ///
  /// In en, this message translates to:
  /// **'Late arrival (hourly)'**
  String get lateArrivalHourly;

  /// No description provided for @earlyLeaveHourly.
  ///
  /// In en, this message translates to:
  /// **'Early leave (hourly)'**
  String get earlyLeaveHourly;

  /// No description provided for @excusedAbsenceFullDay.
  ///
  /// In en, this message translates to:
  /// **'Excused absence (full day)'**
  String get excusedAbsenceFullDay;

  /// No description provided for @dateField.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateField;

  /// No description provided for @timeField.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeField;

  /// No description provided for @fromField.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromField;

  /// No description provided for @toField.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toField;

  /// No description provided for @periodField.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get periodField;

  /// No description provided for @daysExceedBalance.
  ///
  /// In en, this message translates to:
  /// **'Requested days ({requested}) exceed your remaining balance ({remaining})'**
  String daysExceedBalance(Object requested, Object remaining);

  /// No description provided for @reasonField.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reasonField;

  /// No description provided for @reasonHint.
  ///
  /// In en, this message translates to:
  /// **'Briefly describe the reason'**
  String get reasonHint;

  /// No description provided for @attachmentOptional.
  ///
  /// In en, this message translates to:
  /// **'Attachment (optional)'**
  String get attachmentOptional;

  /// No description provided for @cameraLabel.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraLabel;

  /// No description provided for @galleryLabel.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryLabel;

  /// No description provided for @sendingRequest.
  ///
  /// In en, this message translates to:
  /// **'Uploading the attachment and sending your request…'**
  String get sendingRequest;

  /// No description provided for @enterLeaveReason.
  ///
  /// In en, this message translates to:
  /// **'Enter the reason for the leave or excuse'**
  String get enterLeaveReason;

  /// No description provided for @annualNotActive.
  ///
  /// In en, this message translates to:
  /// **'Annual leave isn\'t active on your account yet. Choose another type.'**
  String get annualNotActive;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'Your request was sent to your supervisor and is pending review.'**
  String get requestSent;

  /// No description provided for @sendRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the request: {error}'**
  String sendRequestFailed(Object error);

  /// No description provided for @sendingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sendingEllipsis;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration: {duration}'**
  String durationLabel(Object duration);

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @senderRoleSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get senderRoleSystem;

  /// No description provided for @senderRoleCompanySupervisor.
  ///
  /// In en, this message translates to:
  /// **'Company supervisor'**
  String get senderRoleCompanySupervisor;

  /// No description provided for @senderRoleOrgAdmin.
  ///
  /// In en, this message translates to:
  /// **'Organization admin'**
  String get senderRoleOrgAdmin;

  /// No description provided for @senderRoleBranchesMarketing.
  ///
  /// In en, this message translates to:
  /// **'Branch marketing'**
  String get senderRoleBranchesMarketing;

  /// No description provided for @senderRolePromotionMarketing.
  ///
  /// In en, this message translates to:
  /// **'Promotion marketing'**
  String get senderRolePromotionMarketing;

  /// No description provided for @senderRoleMarketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get senderRoleMarketing;

  /// No description provided for @senderRoleTechSupport.
  ///
  /// In en, this message translates to:
  /// **'Tech support'**
  String get senderRoleTechSupport;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code: {code}'**
  String codeLabel(Object code);

  /// No description provided for @policyOfficialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Official list of violations and fines'**
  String get policyOfficialSubtitle;

  /// No description provided for @catBranchRules.
  ///
  /// In en, this message translates to:
  /// **'Branch rule violation'**
  String get catBranchRules;

  /// No description provided for @catTheftDamage.
  ///
  /// In en, this message translates to:
  /// **'Theft / damage'**
  String get catTheftDamage;

  /// No description provided for @chainCarrefour.
  ///
  /// In en, this message translates to:
  /// **'Carrefour'**
  String get chainCarrefour;

  /// No description provided for @chainBeitElGomla.
  ///
  /// In en, this message translates to:
  /// **'Beit El Gomla'**
  String get chainBeitElGomla;

  /// No description provided for @penSelectBranchesFirst.
  ///
  /// In en, this message translates to:
  /// **'Select one or more branches to pin as the default'**
  String get penSelectBranchesFirst;

  /// No description provided for @penDefaultUnpinned.
  ///
  /// In en, this message translates to:
  /// **'Default branch group unpinned'**
  String get penDefaultUnpinned;

  /// No description provided for @penBranchPinned.
  ///
  /// In en, this message translates to:
  /// **'Branch pinned as the default for fines'**
  String get penBranchPinned;

  /// No description provided for @penBranchesPinned.
  ///
  /// In en, this message translates to:
  /// **'{count} branches pinned as the default for fines'**
  String penBranchesPinned(Object count);

  /// No description provided for @penSelectDisplayBranches.
  ///
  /// In en, this message translates to:
  /// **'Select branches to show'**
  String get penSelectDisplayBranches;

  /// No description provided for @penShowingAllBranches.
  ///
  /// In en, this message translates to:
  /// **'Showing all branches'**
  String get penShowingAllBranches;

  /// No description provided for @penBranchesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} branches selected'**
  String penBranchesSelected(Object count);

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @searchBranchName.
  ///
  /// In en, this message translates to:
  /// **'Search by branch name…'**
  String get searchBranchName;

  /// No description provided for @allBranchesAll.
  ///
  /// In en, this message translates to:
  /// **'All branches'**
  String get allBranchesAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @noMatchingBranches.
  ///
  /// In en, this message translates to:
  /// **'No matching branches'**
  String get noMatchingBranches;

  /// No description provided for @inDefault.
  ///
  /// In en, this message translates to:
  /// **'In default'**
  String get inDefault;

  /// No description provided for @confirmShowAllBranches.
  ///
  /// In en, this message translates to:
  /// **'Confirm (all branches)'**
  String get confirmShowAllBranches;

  /// No description provided for @confirmFilterCount.
  ///
  /// In en, this message translates to:
  /// **'Confirm filter ({count} branches)'**
  String confirmFilterCount(Object count);

  /// No description provided for @finesSection.
  ///
  /// In en, this message translates to:
  /// **'Fines and violations'**
  String get finesSection;

  /// No description provided for @promoNoFinesAccess.
  ///
  /// In en, this message translates to:
  /// **'Promotion marketing accounts can\'t access fines and violations'**
  String get promoNoFinesAccess;

  /// No description provided for @myViolationsTitle.
  ///
  /// In en, this message translates to:
  /// **'My violations'**
  String get myViolationsTitle;

  /// No description provided for @violationsRecord.
  ///
  /// In en, this message translates to:
  /// **'Violations and fines'**
  String get violationsRecord;

  /// No description provided for @finesSettings.
  ///
  /// In en, this message translates to:
  /// **'Fines settings and policy'**
  String get finesSettings;

  /// No description provided for @recordViolation.
  ///
  /// In en, this message translates to:
  /// **'Record violation'**
  String get recordViolation;

  /// No description provided for @unknownCompany.
  ///
  /// In en, this message translates to:
  /// **'Unknown company'**
  String get unknownCompany;

  /// No description provided for @allBranchesOverview.
  ///
  /// In en, this message translates to:
  /// **'All branches'**
  String get allBranchesOverview;

  /// No description provided for @selectedGroupCount.
  ///
  /// In en, this message translates to:
  /// **'Selected group ({count} branches)'**
  String selectedGroupCount(Object count);

  /// No description provided for @finesPolicyCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The deduction for each violation, first time and when repeated'**
  String get finesPolicyCardSubtitle;

  /// No description provided for @showViolationsFor.
  ///
  /// In en, this message translates to:
  /// **'Show violations for branch / group:'**
  String get showViolationsFor;

  /// No description provided for @unpinDefaultGroup.
  ///
  /// In en, this message translates to:
  /// **'Unpin default group'**
  String get unpinDefaultGroup;

  /// No description provided for @pinSelectedAsDefault.
  ///
  /// In en, this message translates to:
  /// **'Pin selected branches as default'**
  String get pinSelectedAsDefault;

  /// No description provided for @refreshFinesData.
  ///
  /// In en, this message translates to:
  /// **'Refresh fines data'**
  String get refreshFinesData;

  /// No description provided for @finesDataRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Fines data refreshed'**
  String get finesDataRefreshed;

  /// No description provided for @pinnedDefaultGroup.
  ///
  /// In en, this message translates to:
  /// **'Pinned default group'**
  String get pinnedDefaultGroup;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @mySummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get mySummary;

  /// No description provided for @finesSummaryOf.
  ///
  /// In en, this message translates to:
  /// **'Fines summary ({branch})'**
  String finesSummaryOf(Object branch);

  /// No description provided for @companiesFinesSummary.
  ///
  /// In en, this message translates to:
  /// **'Fines summary by company'**
  String get companiesFinesSummary;

  /// No description provided for @finesSummary.
  ///
  /// In en, this message translates to:
  /// **'Fines summary'**
  String get finesSummary;

  /// No description provided for @myTotalFines.
  ///
  /// In en, this message translates to:
  /// **'Total fines'**
  String get myTotalFines;

  /// No description provided for @totalFines.
  ///
  /// In en, this message translates to:
  /// **'Total fines'**
  String get totalFines;

  /// No description provided for @deductedFromMe.
  ///
  /// In en, this message translates to:
  /// **'Deducted'**
  String get deductedFromMe;

  /// No description provided for @deducted.
  ///
  /// In en, this message translates to:
  /// **'Deducted'**
  String get deducted;

  /// No description provided for @violationsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Violations'**
  String get violationsCountLabel;

  /// No description provided for @companiesCount.
  ///
  /// In en, this message translates to:
  /// **'Companies'**
  String get companiesCount;

  /// No description provided for @companiesN.
  ///
  /// In en, this message translates to:
  /// **'{count} companies'**
  String companiesN(Object count);

  /// No description provided for @filterByCompany.
  ///
  /// In en, this message translates to:
  /// **'Filter by company:'**
  String get filterByCompany;

  /// No description provided for @allCompaniesCount.
  ///
  /// In en, this message translates to:
  /// **'All companies ({count})'**
  String allCompaniesCount(Object count);

  /// No description provided for @recordClean.
  ///
  /// In en, this message translates to:
  /// **'Your record is clean!'**
  String get recordClean;

  /// No description provided for @noViolationsAnyCompany.
  ///
  /// In en, this message translates to:
  /// **'No violations recorded for any company yet'**
  String get noViolationsAnyCompany;

  /// No description provided for @noViolationsThisCompany.
  ///
  /// In en, this message translates to:
  /// **'No violations recorded for this company'**
  String get noViolationsThisCompany;

  /// No description provided for @noViolationsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No violations recorded.'**
  String get noViolationsRecorded;

  /// No description provided for @rejectionReason.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason'**
  String get rejectionReason;

  /// No description provided for @rejectionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Write the reason for rejecting this violation…'**
  String get rejectionReasonHint;

  /// No description provided for @confirmRejection.
  ///
  /// In en, this message translates to:
  /// **'Confirm rejection'**
  String get confirmRejection;

  /// No description provided for @repeatedViolation.
  ///
  /// In en, this message translates to:
  /// **'Repeated violation'**
  String get repeatedViolation;

  /// No description provided for @confidential.
  ///
  /// In en, this message translates to:
  /// **'Confidential'**
  String get confidential;

  /// No description provided for @targetDelegate.
  ///
  /// In en, this message translates to:
  /// **'Delegate: {name}'**
  String targetDelegate(Object name);

  /// No description provided for @violationDetails.
  ///
  /// In en, this message translates to:
  /// **'Violation details:'**
  String get violationDetails;

  /// No description provided for @branchesMarketingApproval.
  ///
  /// In en, this message translates to:
  /// **'Branch marketing manager approval: {name}'**
  String branchesMarketingApproval(Object name);

  /// No description provided for @generalManagerApproval.
  ///
  /// In en, this message translates to:
  /// **'General manager approval: {name}'**
  String generalManagerApproval(Object name);

  /// No description provided for @attachmentsCount.
  ///
  /// In en, this message translates to:
  /// **'Attachments ({count})'**
  String attachmentsCount(Object count);

  /// No description provided for @tapToPreview2.
  ///
  /// In en, this message translates to:
  /// **'Tap to preview'**
  String get tapToPreview2;

  /// No description provided for @editorName.
  ///
  /// In en, this message translates to:
  /// **'Recorded by: {name}'**
  String editorName(Object name);

  /// No description provided for @documentsCount.
  ///
  /// In en, this message translates to:
  /// **'Documents ({count})'**
  String documentsCount(Object count);

  /// No description provided for @approveAction.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approveAction;

  /// No description provided for @rejectAction.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get rejectAction;

  /// No description provided for @violationsWithCount.
  ///
  /// In en, this message translates to:
  /// **'Violations: {count}'**
  String violationsWithCount(Object count);

  /// No description provided for @totalWithValue.
  ///
  /// In en, this message translates to:
  /// **'Total: {value}'**
  String totalWithValue(Object value);

  /// No description provided for @deductedWithValue.
  ///
  /// In en, this message translates to:
  /// **'Deducted: {value}'**
  String deductedWithValue(Object value);

  /// No description provided for @catUnauthorizedPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photography without permission'**
  String get catUnauthorizedPhoto;

  /// No description provided for @catDataMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing data / features not enabled'**
  String get catDataMissing;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @themeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeModeTitle;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeModeSystem;

  /// No description provided for @themeModeSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Follows your phone\'s dark theme setting'**
  String get themeModeSystemHint;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @taskImageAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach image'**
  String get taskImageAttach;

  /// No description provided for @taskImageFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get taskImageFromCamera;

  /// No description provided for @taskImageFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get taskImageFromGallery;

  /// No description provided for @taskImageReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get taskImageReplace;

  /// No description provided for @taskImageRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get taskImageRemove;

  /// No description provided for @taskImageUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading image…'**
  String get taskImageUploading;

  /// No description provided for @taskImageUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the image. Try again.'**
  String get taskImageUploadFailed;

  /// No description provided for @taskImageRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get taskImageRetry;

  /// No description provided for @taskImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the image'**
  String get taskImageLoadFailed;

  /// No description provided for @taskImageAttached.
  ///
  /// In en, this message translates to:
  /// **'Attached image'**
  String get taskImageAttached;

  /// No description provided for @taskImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The image is too large. Choose a smaller one.'**
  String get taskImageTooLarge;

  /// No description provided for @taskImageAttachAnother.
  ///
  /// In en, this message translates to:
  /// **'Attach another image'**
  String get taskImageAttachAnother;

  /// No description provided for @taskImageMaxReached.
  ///
  /// In en, this message translates to:
  /// **'You can attach up to 3 images'**
  String get taskImageMaxReached;

  /// No description provided for @taskProofTitle.
  ///
  /// In en, this message translates to:
  /// **'Proof of work'**
  String get taskProofTitle;

  /// No description provided for @taskProofAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach proof'**
  String get taskProofAttach;

  /// No description provided for @taskProofBy.
  ///
  /// In en, this message translates to:
  /// **'Proof of work — {name}'**
  String taskProofBy(String name);

  /// No description provided for @taskProofSave.
  ///
  /// In en, this message translates to:
  /// **'Save proof photos'**
  String get taskProofSave;

  /// No description provided for @taskEditedLabel.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get taskEditedLabel;

  /// No description provided for @taskEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get taskEditAction;

  /// No description provided for @taskDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get taskDeleteAction;

  /// No description provided for @taskMoreActions.
  ///
  /// In en, this message translates to:
  /// **'Task options'**
  String get taskMoreActions;

  /// No description provided for @taskCloseImage.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get taskCloseImage;

  /// Splash stall message
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect'**
  String get splashConnectionFailed;

  /// Splash retry button
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get splashRetry;

  /// Splash go-to-login button
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get splashSignIn;

  /// Map gate timeout message
  ///
  /// In en, this message translates to:
  /// **'Map unavailable'**
  String get mapUnavailable;

  /// Map gate retry button
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get mapRetry;

  /// Title of the device-binding security dialog
  ///
  /// In en, this message translates to:
  /// **'Security alert: this account is bound to another device'**
  String get deviceLockTitle;

  /// Mandatory button when an unbind request is already pending
  ///
  /// In en, this message translates to:
  /// **'Unbind request pending review'**
  String get deviceLockPendingUnbindButton;

  /// Mandatory button to submit a device unbind request
  ///
  /// In en, this message translates to:
  /// **'Send an unbind request'**
  String get deviceLockSendUnbindButton;

  /// Busy label while the unbind request is being sent
  ///
  /// In en, this message translates to:
  /// **'Sending request...'**
  String get deviceLockSubmitting;

  /// Confirmation after the unbind request is sent or already pending
  ///
  /// In en, this message translates to:
  /// **'The request was sent to the supervisor'**
  String get deviceLockRequestSent;

  /// Error when the dialog has no delegate to attach the unbind request to
  ///
  /// In en, this message translates to:
  /// **'Could not identify the delegate to send the request'**
  String get deviceLockCannotIdentifyDelegate;

  /// Error snackbar when sending the unbind request fails
  ///
  /// In en, this message translates to:
  /// **'Could not send the request: {error}'**
  String deviceLockSendError(String error);

  /// Label for the multi-select chain picker on the add-delegate form
  ///
  /// In en, this message translates to:
  /// **'Target organization / retail chain'**
  String get chainPickerTitle;

  /// Select or deselect every chain in the add-delegate picker
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get chainPickerSelectAll;

  /// Explains that multi-chain registration is one subscription with no per-chain fee
  ///
  /// In en, this message translates to:
  /// **'One request, one approval, and one subscription. There is no per-chain fee.'**
  String get chainPickerOneSubscriptionNote;

  /// Error when the supervisor submits without selecting a chain
  ///
  /// In en, this message translates to:
  /// **'Please select at least one chain.'**
  String get chainPickerRequired;

  /// Title of the forced-update page shown when the installed build is below the minimum version (TAS-66)
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequiredTitle;

  /// Body of the forced-update page
  ///
  /// In en, this message translates to:
  /// **'This version of Tashil is no longer supported. Please install the latest update to continue.'**
  String get updateRequiredBody;

  /// Small line showing the installed and the minimum version
  ///
  /// In en, this message translates to:
  /// **'Installed version {current} · minimum {minimum}'**
  String updateRequiredVersions(String current, String minimum);

  /// Button that opens the app store page
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateRequiredButton;

  /// Shown instead of the button when no store link is configured for this platform
  ///
  /// In en, this message translates to:
  /// **'Open the App Store and update Tashil, then open the app again.'**
  String get updateRequiredNoStoreLink;

  /// Snackbar when the store link could not be launched
  ///
  /// In en, this message translates to:
  /// **'Could not open the store. Please open it yourself and update Tashil.'**
  String get updateRequiredOpenFailed;
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
