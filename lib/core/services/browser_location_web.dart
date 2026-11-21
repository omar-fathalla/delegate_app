import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `location.pathname`, `location.search`, `location.hash` and the
/// `<base href>` of the page.
({String path, String query, String hash, String base})? readBrowserLocation() {
  final location = globalContext.getProperty<JSObject>('location'.toJS);
  String read(String name) =>
      location.getProperty<JSString?>(name.toJS)?.toDart ?? '';
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final baseElement = document.callMethod<JSObject?>(
    'querySelector'.toJS,
    'base'.toJS,
  );
  final base = baseElement
      ?.callMethod<JSString?>('getAttribute'.toJS, 'href'.toJS)
      ?.toDart;
  return (
    path: read('pathname'),
    query: read('search'),
    hash: read('hash'),
    base: base ?? '/',
  );
}

/// `history.replaceState(null, '', url)`: changes the address without a
/// reload or a new history entry.
void replaceBrowserUrl(String url) {
  final history = globalContext.getProperty<JSObject>('history'.toJS);
  // callMethod drops a null first argument; the state must be passed.
  history.callMethodVarArgs('replaceState'.toJS, [null, ''.toJS, url.toJS]);
}
