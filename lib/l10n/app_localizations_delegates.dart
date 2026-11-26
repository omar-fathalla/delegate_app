import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart'
    show GlobalMaterialLocalizations;

import 'app_localizations.dart';

/// Localization delegates for the app (TAS-374).
///
/// Use this instead of the generated `AppLocalizations.localizationsDelegates`:
/// `flutter gen-l10n` still emits the Material and Cupertino delegates from
/// `flutter_localizations`, which belong to the deprecated
/// `package:flutter/material.dart`. The app's widgets now come from
/// `material_ui` / `cupertino_ui`, which look up their own
/// `MaterialLocalizations` / `CupertinoLocalizations` types.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
