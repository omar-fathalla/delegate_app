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

  /// Delegate app subtitle
  ///
  /// In en, this message translates to:
  /// **'Delegate App'**
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
  /// **'Scan for {action}'**
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
  /// **'Help Center'**
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
