import 'package:delegate_app/core/config/app_env.dart';
import 'package:flutter/foundation.dart';

/// DEV-only switch to hang auto-login on web (`?debugStall=1`), so the splash
/// stall screen can be tested in a browser. Always false outside ENV=dev.
bool get debugStallActive =>
    AppEnv.isDev && debugStallActiveFor(env: AppEnv.name, isWeb: kIsWeb, uri: Uri.base);

/// Pure rule behind [debugStallActive]; exposed for tests.
bool debugStallActiveFor({
  required String env,
  required bool isWeb,
  required Uri uri,
}) {
  if (env != 'dev' || !isWeb) return false;
  if (uri.queryParameters['debugStall'] == '1') return true;
  // Hash routing: also accept /#/?debugStall=1
  final frag = uri.fragment;
  final q = frag.indexOf('?');
  if (q < 0) return false;
  return Uri.splitQueryString(frag.substring(q + 1))['debugStall'] == '1';
}
