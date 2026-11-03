import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void reloadPage() {
  final location = globalContext.getProperty<JSObject>('location'.toJS);
  location.callMethod('reload'.toJS);
}
