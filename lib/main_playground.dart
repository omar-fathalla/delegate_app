import 'package:material_ui/material_ui.dart';

import 'core/design/app_localizations.dart';
import 'core/design/color_schemes.dart';
import 'features/playground/playground_screen.dart';

/// Standalone entry point for the component playground, no database needed:
///
///     flutter run -t lib/main_playground.dart
void main() => runApp(const PlaygroundApp());

class PlaygroundApp extends StatefulWidget {
  const PlaygroundApp({super.key});

  @override
  State<PlaygroundApp> createState() => _PlaygroundAppState();
}

class _PlaygroundAppState extends State<PlaygroundApp> {
  final _colors = TashilColorController();

  @override
  void dispose() {
    _colors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TashilColorScope(
    controller: _colors,
    builder: (context, themes) => MaterialApp(
      title: 'Tashil Delegate · Material 3',
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      // System high-contrast setting (M3: three contrast levels).
      highContrastTheme: themes.highContrastLight,
      highContrastDarkTheme: themes.highContrastDark,
      locale: TashilLocale.arabic,
      supportedLocales: TashilLocale.supported,
      localizationsDelegates: TashilLocale.delegates,
      home: const PlaygroundScreen(),
    ),
  );
}
