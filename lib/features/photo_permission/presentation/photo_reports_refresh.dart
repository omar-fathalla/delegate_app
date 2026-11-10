import 'package:flutter/foundation.dart';

/// The camera route and the photo-reports tab each create their own
/// [PhotoPermissionBloc] (GetIt factory). Upload success on the camera
/// bloc therefore never reaches the reports tab's listener. This
/// listenable is the cross-bloc "please reload" signal.
class PhotoReportsRefresh {
  PhotoReportsRefresh._();
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void request() => tick.value++;
}
