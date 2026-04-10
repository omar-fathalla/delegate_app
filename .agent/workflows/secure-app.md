---
description: Add biometric authentication, Firebase App Check, and SSL pinning for production-grade security.
---

# Secure the App

## 1. Biometric Authentication (local_auth)

### Add dependency

// turbo
```
flutter pub add local_auth
```

### Android configuration

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.USE_FINGERPRINT" />
```

### iOS configuration

Add to `ios/Runner/Info.plist`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>نحتاج للتحقق من هويتك لفتح التطبيق</string>
```

### Implementation

```dart
import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    return await _localAuth.canCheckBiometrics ||
           await _localAuth.isDeviceSupported();
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'يرجى التحقق من هويتك لفتح التطبيق',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,  // Allow PIN/pattern fallback
        ),
      );
    } catch (e) {
      return false;
    }
  }
}
```

### Use in app startup

```dart
// In splash screen or app initialization
final biometricService = sl<BiometricService>();
if (await biometricService.isBiometricAvailable()) {
  final authenticated = await biometricService.authenticate();
  if (!authenticated) {
    // Show locked screen or exit
    return;
  }
}
// Proceed to home
```

## 2. Firebase App Check

### Add dependency

// turbo
```
flutter pub add firebase_app_check
```

### Initialize in main.dart

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

// App Check — MUST be after Firebase.initializeApp()
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.playIntegrity,  // Production
  appleProvider: AppleProvider.deviceCheck,         // Production
  // For debug/development use:
  // androidProvider: AndroidProvider.debug,
  // appleProvider: AppleProvider.debug,
);
```

### Enable in Firebase Console
1. Go to Firebase Console → App Check
2. Enable Play Integrity (Android) and DeviceCheck (iOS)
3. Enforce for Firestore, Storage, and Auth

## 3. Data Scope Protection

```dart
// ✅ CORRECT: Only access own data
final delegate = await firestore
  .collection('organizations').doc(orgId)
  .collection('companies').doc(compId)
  .collection('delegates').doc(currentUser.uid)  // Own UID only
  .get();

// ❌ WRONG: Never query all delegates
final allDelegates = await firestore
  .collectionGroup('delegates')
  .get();
```

## 4. Secure Storage for Sensitive Data

// turbo
```
flutter pub add flutter_secure_storage
```

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorage = FlutterSecureStorage();

// Store sensitive token
await secureStorage.write(key: 'auth_token', value: token);

// Read
final token = await secureStorage.read(key: 'auth_token');

// Delete on logout
await secureStorage.deleteAll();
```

## 5. Security Checklist

- [ ] `local_auth` enabled for app launch
- [ ] Firebase App Check activated (Play Integrity / DeviceCheck)
- [ ] No `print()` — use `debugPrint()` only
- [ ] No hardcoded keys — all in `firebase_options.dart`
- [ ] Only `delegates/{currentUser.uid}` data synced locally
- [ ] `flutter_secure_storage` for sensitive tokens
- [ ] Mock location detection active in attendance
- [ ] Firestore Security Rules enforce `uid == request.auth.uid`

## 6. Register in DI

```dart
// Biometric
sl.registerLazySingleton(() => BiometricService());

// Secure Storage
sl.registerLazySingleton(() => const FlutterSecureStorage());
```

## 7. Verify

// turbo
```
flutter analyze
```
