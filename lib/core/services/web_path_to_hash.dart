import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/browser_location_stub.dart'
    if (dart.library.js_interop) 'package:delegate_app/core/services/browser_location_web.dart';

/// Web addresses with a path and no hash (TAS-197).
///
/// The web app routes on the hash (`/#/hr/home`). Hosting serves the app for
/// any path, so a link or a typed address like `https://host/hr/home` loads
/// it with the path kept: the router then appends its hash and the address
/// becomes `/hr/home#/hr/home`, later `/hr/home#/hr/leaves`. Before the
/// router reads the address, [normalizeWebPathToHash] moves the path into
/// the hash: `/hr/home` → `/#/hr/home` (see [hashAddressForPath]). Mobile
/// does nothing.
abstract final class WebPathToHash {
  /// Tests replace the browser address (path, query, hash, `<base href>`).
  @visibleForTesting
  static ({String path, String query, String hash, String base})? Function()?
  debugReadLocation;

  /// Tests capture the replaced address.
  @visibleForTesting
  static void Function(String url)? debugReplaceUrl;

  @visibleForTesting
  static void debugReset() {
    debugReadLocation = null;
    debugReplaceUrl = null;
  }
}

/// The hash address for a browser address with a [path] under [base], or
/// null when nothing should change.
///
/// `/hr/home` → `/#/hr/home`; `/hr/leaves?x=1` → `/#/hr/leaves?x=1`. An
/// address the old bug already broke keeps its hash and loses the stray
/// path: `/hr/home#/hr/leaves` → `/#/hr/leaves`. The root and `index.html`
/// stay as they are, and so does a hash that is not a route (`#token`).
String? hashAddressForPath({
  required String path,
  String query = '',
  String hash = '',
  String base = '/',
}) {
  var basePath = Uri.tryParse(base)?.path ?? '/';
  if (!basePath.startsWith('/')) basePath = '/$basePath';
  if (!basePath.endsWith('/')) basePath = '$basePath/';
  if (!path.startsWith(basePath)) return null;
  var rest = path.substring(basePath.length);
  while (rest.endsWith('/')) {
    rest = rest.substring(0, rest.length - 1);
  }
  if (rest.isEmpty || rest == 'index.html') return null;
  if (hash.isEmpty || hash == '#') return '$basePath#/$rest$query';
  if (hash.startsWith('#/')) return '$basePath$query$hash';
  return null;
}

/// Web only: rewrites `/hr/home` to `/#/hr/home` in place (no reload, no
/// new history entry). Call before the router reads the address.
void normalizeWebPathToHash() {
  if (!WebRuntimePolicy.isWeb) return;
  final location = (WebPathToHash.debugReadLocation ?? readBrowserLocation)
      .call();
  if (location == null) return;
  final address = hashAddressForPath(
    path: location.path,
    query: location.query,
    hash: location.hash,
    base: location.base,
  );
  if (address == null) return;
  (WebPathToHash.debugReplaceUrl ?? replaceBrowserUrl)(address);
}
