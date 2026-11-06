import Flutter
import UIKit
import FirebaseCore
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Initialize Google Maps SDK - read API key from Info.plist
    // (GMS_API_KEY from ios/Flutter/Env-<env>.xcconfig).
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      GMSServices.provideAPIKey(apiKey)
    } else {
      print("⚠️ Google Maps API Key not found in Info.plist")
      print("⚠️ Add GMSApiKey to your Info.plist file")
    }
    
    // Configure Firebase natively only for prod. TashilEnv is written into the
    // built Info.plist by ios/scripts/firebase_config.sh from the Xcode
    // configuration (APP_ENV).
    // - prod: unchanged behaviour, FirebaseApp.configure() from the bundled plist.
    // - dev: never configure natively. Dart initialises Firebase with the
    //   tashil-dev options after its own ENV guard, so nothing reaches any
    //   Firebase project before Dart runs.
    // - anything else: fail closed (no native Firebase).
    let tashilEnv = Bundle.main.object(forInfoDictionaryKey: "TashilEnv") as? String
    switch tashilEnv {
    case "prod":
      FirebaseApp.configure()
    case "dev":
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
      let projectId = path.flatMap { NSDictionary(contentsOfFile: $0)?["PROJECT_ID"] as? String }
      if projectId != "tashil-dev" {
        NSLog("[Tashil] dev build bundles PROJECT_ID=%@; expected tashil-dev. Firebase stays unconfigured natively.", projectId ?? "nil")
        assertionFailure("dev build must bundle the tashil-dev GoogleService-Info.plist")
      }
    default:
      NSLog("[Tashil] TashilEnv=%@ is not dev/prod; native Firebase not configured.", tashilEnv ?? "nil")
      assertionFailure("TashilEnv missing from Info.plist")
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
