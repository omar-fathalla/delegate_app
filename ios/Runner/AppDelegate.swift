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
      // Never call FirebaseApp.configure() in dev; Dart initializes tashil-dev only.
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
      let projectId = path.flatMap { NSDictionary(contentsOfFile: $0)?["PROJECT_ID"] as? String }
      if projectId != "tashil-dev" {
        NSLog("[Tashil] FATAL: dev build PROJECT_ID=%@ (expected tashil-dev). Refusing to launch.", projectId ?? "nil")
        return false
      }
    default:
      NSLog("[Tashil] FATAL: TashilEnv=%@ is missing or invalid; native Firebase not configured.", tashilEnv ?? "nil")
      return false
    }

    // Google Maps: same fail-closed order as Firebase — only after TashilEnv /
    // plist validation for this flavor (GMSApiKey from ios/Flutter/Env-*.xcconfig).
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      GMSServices.provideAPIKey(apiKey)
    } else {
      print("⚠️ Google Maps API Key not found in Info.plist")
      print("⚠️ Add GMSApiKey to your Info.plist file")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
