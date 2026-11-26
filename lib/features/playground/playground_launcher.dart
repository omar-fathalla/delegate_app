import 'package:material_ui/material_ui.dart';

import '../../core/design/color_schemes.dart';
import 'playground_screen.dart';

/// Opens the m3-kit component playground inside the app (TAS-383).
///
/// Only reachable from dev builds (settings, `AppEnv.isDev`), so the team can
/// compare a screen with the design system's own examples on a real device.
/// The playground keeps its own colour controller (source, contrast) and its
/// app bar toggles dark mode, RTL/LTR, large text and contrast, without
/// touching the app's theme settings.
class PlaygroundLauncher extends StatefulWidget {
  const PlaygroundLauncher({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PlaygroundLauncher()));

  @override
  State<PlaygroundLauncher> createState() => _PlaygroundLauncherState();
}

class _PlaygroundLauncherState extends State<PlaygroundLauncher> {
  final _colors = TashilColorController();

  @override
  void dispose() {
    _colors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TashilColorScope(
    controller: _colors,
    builder: (context, _) => const PlaygroundScreen(),
  );
}
