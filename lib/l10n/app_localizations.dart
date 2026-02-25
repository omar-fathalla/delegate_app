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
  /// **'Tashil - Delegate'**
  String get appTitle;

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
  /// **'Login to continue'**
  String get loginToContinue;

  /// Login success snackbar
  ///
  /// In en, this message translates to:
  /// **'Login Successful!'**
  String get loginSuccessful;

  /// Login button text
  ///
  /// In en, this message translates to:
  /// **'LOGIN'**
  String get loginButton;

  /// Mobile number field label
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
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

  /// Close button tooltip
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Open in browser tooltip
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;
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
