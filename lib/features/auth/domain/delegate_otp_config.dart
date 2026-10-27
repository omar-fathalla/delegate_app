import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Client gate for the delegate phone OTP step.
///
/// Precedence, highest first:
/// 1. `--dart-define=DELEGATE_OTP_ENABLED=true` forces the step on for a
///    local build. A compiled `false` is not an override: `bool.fromEnvironment`
///    cannot tell "unset" from "false", and treating false as a pin would
///    stop Remote Config from ever turning the step on.
/// 2. A test (or other runtime) assignment to [enabled] pins the value.
/// 3. Firebase Remote Config key [remoteKey], read at the moment of use.
/// 4. In-app default `false` when the key was never fetched or the read fails.
///
/// [refreshFromRemoteConfig] is started once after `Firebase.initializeApp`
/// and is not awaited. Login calls [enabled] when the session is known, so
/// a fetch that finishes while the user is typing is the value that applies.
///
/// This flag is not proof of possession. `delegateLoginV2` still issues a
/// custom token before any SMS is sent, and Firestore rules do not read a
/// phone provider. A later change can set `phone_number` on that token
/// (or require `request.auth.token.phone_number` / the phone identity to
/// match the delegate) and refuse delegate reads until it does. Do not
/// treat a client-side OTP screen as that control. The in-app default is
/// the only default shipped with the app; this code does not publish a
/// Remote Config template.
abstract final class DelegateOtpConfig {
  static const String remoteKey = 'delegate_otp_enabled';

  /// Compiled `--dart-define=DELEGATE_OTP_ENABLED=true` forces the step on.
  static const bool dartDefineForcesOn = bool.fromEnvironment(
    'DELEGATE_OTP_ENABLED',
    defaultValue: false,
  );

  static const Duration fetchTimeout = Duration(seconds: 10);
  static const Duration activateTimeout = Duration(seconds: 12);
  static const Duration debugMinimumFetchInterval = Duration.zero;
  static const Duration releaseMinimumFetchInterval = Duration(hours: 1);

  static const Duration resendCooldown = Duration(seconds: 60);

  static bool? _pinned;
  static DelegateOtpFlagSource? _source;

  /// Remote Config value, unless a local override or a test pin wins.
  static bool get enabled => resolveDelegateOtpEnabled(
    dartDefineForcesOn: dartDefineForcesOn,
    pinned: _pinned,
    remoteValue: _remoteOrFalse(),
  );

  /// Pins the flag for tests. Production never assigns this.
  static set enabled(bool value) => _pinned = value;

  static bool _remoteOrFalse() {
    if (dartDefineForcesOn || _pinned != null) return false;
    final source = _source;
    if (source == null) return false;
    try {
      return source.read();
    } catch (error) {
      debugPrint(
        'delegate_otp_enabled unavailable, using in-app default false ($error)',
      );
      return false;
    }
  }

  /// Fetches and activates Remote Config. Never throws. Offline, timeout,
  /// and a missing Firebase app all leave the in-app default (`false`).
  static Future<void> refreshFromRemoteConfig({
    DelegateOtpFlagSource? source,
    Duration timeout = activateTimeout,
  }) async {
    try {
      final flagSource =
          source ??
          FirebaseDelegateOtpFlagSource(FirebaseRemoteConfig.instance);
      await flagSource.prepare().timeout(timeout);
      _source = flagSource;
      try {
        final value = flagSource.read();
        debugPrint(
          'delegate_otp_enabled=$value source=${flagSource.sourceName}',
        );
      } catch (error) {
        debugPrint(
          'delegate_otp_enabled unavailable, using in-app default false ($error)',
        );
      }
    } catch (error) {
      debugPrint(
        'delegate_otp_enabled unavailable, using in-app default false ($error)',
      );
    }
  }

  /// Clears the test pin and any installed flag source.
  @visibleForTesting
  static void debugReset() {
    _pinned = null;
    _source = null;
  }
}

/// Decides the OTP gate. [dartDefineForcesOn] beats [pinned], which beats
/// [remoteValue]. Callers pass `false` for [remoteValue] when no fetch has
/// completed or the read failed.
bool resolveDelegateOtpEnabled({
  required bool dartDefineForcesOn,
  required bool? pinned,
  required bool remoteValue,
}) {
  if (dartDefineForcesOn) return true;
  final override = pinned;
  if (override != null) return override;
  return remoteValue;
}

/// Reads `delegate_otp_enabled` without this library calling Firebase.
abstract interface class DelegateOtpFlagSource {
  Future<void> prepare();
  bool read();

  /// `ValueSource.name` (`valueRemote`, `valueDefault`, `valueStatic`).
  String get sourceName;
}

/// Production source. Constructed only after `Firebase.initializeApp`.
final class FirebaseDelegateOtpFlagSource implements DelegateOtpFlagSource {
  FirebaseDelegateOtpFlagSource(this._remote);

  final FirebaseRemoteConfig _remote;

  @override
  Future<void> prepare() async {
    await _remote.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: DelegateOtpConfig.fetchTimeout,
        minimumFetchInterval: kDebugMode
            ? DelegateOtpConfig.debugMinimumFetchInterval
            : DelegateOtpConfig.releaseMinimumFetchInterval,
      ),
    );
    await _remote.setDefaults(const {DelegateOtpConfig.remoteKey: false});
    await _remote.fetchAndActivate();
  }

  @override
  bool read() => _remote.getBool(DelegateOtpConfig.remoteKey);

  @override
  String get sourceName =>
      _remote.getValue(DelegateOtpConfig.remoteKey).source.name;
}

/// Staff email/password profiles are marked in [Delegate.nationalityID].
/// Delegate documents loaded after `delegateLoginV2` are not.
bool isStaffPasswordProfile(String nationalityId) {
  return nationalityId.startsWith('__firebase_auth__:') ||
      nationalityId.startsWith('__phone_auth__:');
}

/// OTP applies only to the custom-token delegate path, and only when
/// [DelegateOtpConfig.enabled] is on. The flag is read here, not earlier.
bool delegateLoginNeedsPhoneOtp(List<Delegate> delegates) {
  if (!DelegateOtpConfig.enabled || delegates.isEmpty) return false;
  return delegates.every(
    (delegate) => !isStaffPasswordProfile(delegate.nationalityID),
  );
}
