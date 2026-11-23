import 'package:flutter/foundation.dart';

/// TAS-83: `debugPrint` is not stripped from release builds, and many call
/// sites print phone numbers and uids (wallet, push notifications, search).
/// In a release build every `debugPrint` becomes a no-op, so nothing reaches
/// logcat / the iOS console. Debug and profile builds keep their logs.
///
/// `dart:developer` `log()` only goes to the VM service, which release builds
/// do not have, so it needs no guard.
void silenceDebugPrintInRelease({bool releaseMode = kReleaseMode}) {
  if (!releaseMode) return;
  debugPrint = (String? message, {int? wrapWidth}) {};
}

/// Masks all but the last [visible] characters: `01012345678` → `•••••••5678`.
/// For logs that must stay on in every build.
String maskForLog(String? value, {int visible = 4}) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return '';
  if (v.length <= visible) return '•' * v.length;
  return '${'•' * (v.length - visible)}${v.substring(v.length - visible)}';
}
