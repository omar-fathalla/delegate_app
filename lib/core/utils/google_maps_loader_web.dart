import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:delegate_app/core/config/app_env.dart';

bool _scriptInjected = false;

/// Ensures the Google Maps JavaScript SDK script tag is injected into the DOM.
void _ensureScriptInjected() {
  if (_scriptInjected) return;
  try {
    final doc = globalContext.getProperty('document'.toJS);
    if (doc == null || doc.isUndefined || doc.isNull) return;
    final docObj = doc as JSObject;

    // Check if script tag is already in DOM
    final existing = docObj.callMethod(
      'querySelector'.toJS,
      'script[src*="maps.googleapis.com"]'.toJS,
    );
    if (existing != null && !existing.isUndefined && !existing.isNull) {
      _scriptInjected = true;
      return;
    }

    final script =
        docObj.callMethod('createElement'.toJS, 'script'.toJS) as JSObject?;
    if (script == null) return;

    script.setProperty(
      'src'.toJS,
      'https://maps.googleapis.com/maps/api/js?key=${AppEnv.mapsJsApiKey}&libraries=drawing,marker'.toJS,
    );
    script.setProperty('async'.toJS, true.toJS);
    script.setProperty('defer'.toJS, true.toJS);

    final head =
        docObj.callMethod('querySelector'.toJS, 'head'.toJS) as JSObject?;
    if (head != null && !head.isUndefined && !head.isNull) {
      head.callMethod('appendChild'.toJS, script);
      _scriptInjected = true;
    }
  } catch (_) {
    // Graceful fallback
  }
}

/// Checks if Google Maps JavaScript SDK is loaded and available on window.google.maps
bool isGoogleMapsAvailable() {
  try {
    if (!globalContext.hasProperty('google'.toJS).toDart) {
      _ensureScriptInjected();
      return false;
    }
    final google = globalContext.getProperty('google'.toJS);
    if (google == null || google.isUndefined || google.isNull) {
      _ensureScriptInjected();
      return false;
    }
    final googleObj = google as JSObject;
    if (!googleObj.hasProperty('maps'.toJS).toDart) {
      _ensureScriptInjected();
      return false;
    }
    final maps = googleObj.getProperty('maps'.toJS);
    if (maps == null || maps.isUndefined || maps.isNull) {
      _ensureScriptInjected();
      return false;
    }
    final mapsObj = maps as JSObject;
    if (!mapsObj.hasProperty('Map'.toJS).toDart) {
      _ensureScriptInjected();
      return false;
    }
    final map = mapsObj.getProperty('Map'.toJS);
    return map != null && !map.isUndefined && !map.isNull;
  } catch (_) {
    return false;
  }
}


/// Retry after a failed load: replace the Maps <script> with a fresh copy that
/// uses the same src (same key) already in the page, so the browser fetches it
/// again. No-op when Maps is already available or no script tag exists.
void reloadGoogleMapsScript() {
  if (isGoogleMapsAvailable()) return;
  try {
    final doc = globalContext.getProperty('document'.toJS) as JSObject?;
    if (doc == null) return;
    final old = doc.callMethod(
      'querySelector'.toJS,
      'script[src*="maps.googleapis.com/maps/api/js"]'.toJS,
    ) as JSObject?;
    if (old == null) {
      _scriptInjected = false;
      _ensureScriptInjected();
      return;
    }
    final src = old.getProperty('src'.toJS);
    if (src == null || src.isUndefined || src.isNull) return;
    final fresh =
        doc.callMethod('createElement'.toJS, 'script'.toJS) as JSObject?;
    if (fresh == null) return;
    fresh.setProperty('src'.toJS, src);
    fresh.setProperty('async'.toJS, true.toJS);
    old.callMethod('remove'.toJS);
    final head = doc.callMethod('querySelector'.toJS, 'head'.toJS) as JSObject?;
    head?.callMethod('appendChild'.toJS, fresh);
  } catch (_) {
    // Graceful fallback: the gate just waits again.
  }
}
