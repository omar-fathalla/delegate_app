import 'package:material_ui/material_ui.dart';

import '../../core/design/color_schemes.dart';
import '../../core/design/tokens.dart';
import 'sections/actions.dart';
import 'sections/containment.dart';
import 'sections/feedback.dart';
import 'sections/foundations.dart';
import 'sections/inputs.dart';
import 'sections/navigation.dart';
import 'sections/transitions.dart';

/// Component playground: every Material 3 component Tashil uses, rendered
/// with the real app theme. This page is the visual reference for the design
/// rules in `docs/design-system.md`. Toggle dark mode, direction and text
/// size from the app bar to check a component under each condition.
class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  static const tabs = [
    (Icons.palette_outlined, 'الأساسيات'),
    (Icons.smart_button_outlined, 'الأزرار'),
    (Icons.edit_outlined, 'المدخلات'),
    (Icons.explore_outlined, 'التنقل'),
    (Icons.view_agenda_outlined, 'الحاويات'),
    (Icons.notifications_outlined, 'التنبيهات'),
    (Icons.animation, 'الانتقالات'),
  ];

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  bool? _dark; // null = follow the app / system
  bool _rtl = true;
  bool _largeText = false;

  static const _contrastNames = {
    TashilContrast.standard: 'عادي',
    TashilContrast.medium: 'متوسط',
    TashilContrast.high: 'عالي',
  };

  @override
  Widget build(BuildContext context) {
    final appDark = Theme.of(context).brightness == Brightness.dark;
    final dark = _dark ?? appDark;
    // Follows the colour source and contrast chosen in the colour section
    // (TashilColorScope above the app).
    final colors = TashilColorController.of(context);
    final contrast = colors.value.contrast;
    final themes = colors.themes;
    final theme = dark ? themes.dark : themes.light;
    final media = MediaQuery.of(context);

    return Theme(
      data: theme,
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: media.copyWith(
            textScaler: _largeText
                ? const TextScaler.linear(1.3)
                : media.textScaler,
          ),
          // Own messenger so snackbars use the playground theme.
          child: ScaffoldMessenger(
            child: DefaultTabController(
              length: PlaygroundScreen.tabs.length,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('مكونات Material 3'),
                  actions: [
                    IconButton(
                      tooltip: dark ? 'الوضع الفاتح' : 'الوضع الداكن',
                      onPressed: () => setState(() => _dark = !dark),
                      icon: Icon(
                        dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: _rtl ? 'LTR' : 'RTL',
                      onPressed: () => setState(() => _rtl = !_rtl),
                      icon: const Icon(Icons.format_textdirection_r_to_l),
                      isSelected: !_rtl,
                      selectedIcon: const Icon(
                        Icons.format_textdirection_l_to_r,
                      ),
                    ),
                    IconButton(
                      // Cycles the three M3 contrast levels.
                      tooltip: 'التباين: ${_contrastNames[contrast]}',
                      isSelected: contrast != TashilContrast.standard,
                      onPressed: () => colors.update(
                        (s) => s.copyWith(
                          contrast:
                              TashilContrast.values[(contrast.index + 1) %
                                  TashilContrast.values.length],
                        ),
                      ),
                      icon: const Icon(Icons.contrast),
                    ),
                    IconButton(
                      tooltip: 'تكبير الخط',
                      onPressed: () => setState(() => _largeText = !_largeText),
                      isSelected: _largeText,
                      icon: const Icon(Icons.text_increase),
                      selectedIcon: const Icon(Icons.text_decrease),
                    ),
                  ],
                  bottom: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      for (final (icon, label) in PlaygroundScreen.tabs)
                        Tab(icon: Icon(icon), text: label),
                    ],
                  ),
                ),
                body: const TabBarView(
                  children: [
                    FoundationsSection(),
                    ActionsSection(),
                    InputsSection(),
                    NavigationSection(),
                    ContainmentSection(),
                    FeedbackSection(),
                    TransitionsSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
