import 'package:delegate_app/core/config/app_env.dart';
import 'package:flutter/material.dart';

/// Exposes stable [Semantics.identifier] values for Maestro on ENV=dev only.
Widget tashilMaestroDevSemantics({
  required String identifier,
  required Widget child,
  String? label,
  bool button = false,
}) {
  if (!AppEnv.isDev) {
    return child;
  }
  return Semantics(
    identifier: identifier,
    label: label,
    button: button,
    container: true,
    explicitChildNodes: true,
    child: ExcludeSemantics(child: child),
  );
}
