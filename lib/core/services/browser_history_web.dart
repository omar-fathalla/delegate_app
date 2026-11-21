import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `window.history.back()`: the same step as the browser back button.
void browserHistoryBack() {
  final history = globalContext.getProperty<JSObject>('history'.toJS);
  history.callMethod('back'.toJS);
}
