import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'tokens.dart';

/// Where the app's colour scheme comes from. Follows
/// m3.material.io/styles/color/choosing-a-scheme and the static and
/// dynamic scheme pages.
enum TashilColorSource {
  /// Static, Tashil's own green ([TashilColors.seed]). Default: the same
  /// on every device, best for a shop device shared by cashiers.
  brand,

  /// Static, from the store's own brand colour (M3 "custom brand"). Set
  /// once per company by the owner; every device of that store matches.
  store,

  /// Dynamic, user-generated: from the device wallpaper (Android 12+).
  /// Falls back to [brand] where the system offers no wallpaper colour.
  wallpaper,

  /// Static M3 baseline scheme (the purple Material default). Mostly for
  /// checking designs against M3 references.
  baseline,
}

/// The M3 baseline source colour.
const baselineSeed = Color(0xFF6750A4);

/// Store brand colours offered to owners. Any colour works; these are a
/// starting point that read well as sources.
const storeColorPresets = <Color>[
  Color(0xFF1565C0),
  Color(0xFFC62828),
  Color(0xFF6A1B9A),
  Color(0xFFEF6C00),
  Color(0xFF00838F),
  Color(0xFF4E342E),
];

@immutable
class TashilColorSettings {
  const TashilColorSettings({
    this.source = TashilColorSource.brand,
    this.storeColor = const Color(0xFF1565C0),
    this.fidelity = false,
    this.contrast = TashilContrast.standard,
  });

  final TashilColorSource source;
  final Color storeColor;

  /// Keep the scheme close to the source colour (M3 "chroma fidelity",
  /// `DynamicSchemeVariant.fidelity`). Useful for a strong brand colour.
  final bool fidelity;
  final TashilContrast contrast;

  TashilColorSettings copyWith({
    TashilColorSource? source,
    Color? storeColor,
    bool? fidelity,
    TashilContrast? contrast,
  }) => TashilColorSettings(
    source: source ?? this.source,
    storeColor: storeColor ?? this.storeColor,
    fidelity: fidelity ?? this.fidelity,
    contrast: contrast ?? this.contrast,
  );

  /// The source colour, given the wallpaper colour when the system has one.
  Color seed({Color? wallpaper}) => switch (source) {
    TashilColorSource.brand => TashilColors.seed,
    TashilColorSource.store => storeColor,
    TashilColorSource.wallpaper => wallpaper ?? TashilColors.seed,
    TashilColorSource.baseline => baselineSeed,
  };

  DynamicSchemeVariant get variant =>
      fidelity && source != TashilColorSource.baseline
      ? DynamicSchemeVariant.fidelity
      : DynamicSchemeVariant.tonalSpot;

  @override
  bool operator ==(Object other) =>
      other is TashilColorSettings &&
      other.source == source &&
      other.storeColor == storeColor &&
      other.fidelity == fidelity &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(source, storeColor, fidelity, contrast);
}

/// The four themes [MaterialApp] needs.
typedef TashilThemes = ({
  ThemeData light,
  ThemeData dark,
  ThemeData highContrastLight,
  ThemeData highContrastDark,
});

/// Builds the themes for [settings]. [wallpaper] is the system's
/// wallpaper colour, if any.
TashilThemes themesFor(TashilColorSettings settings, {Color? wallpaper}) {
  final seed = settings.seed(wallpaper: wallpaper);
  final v = settings.variant;
  return (
    light: TashilTheme.light(
      contrast: settings.contrast,
      seed: seed,
      variant: v,
    ),
    dark: TashilTheme.dark(contrast: settings.contrast, seed: seed, variant: v),
    highContrastLight: TashilTheme.light(
      contrast: TashilContrast.high,
      seed: seed,
      variant: v,
    ),
    highContrastDark: TashilTheme.dark(
      contrast: TashilContrast.high,
      seed: seed,
      variant: v,
    ),
  );
}

/// Holds the colour settings. A settings screen changes it; the app
/// rebuilds its themes. (Saving the choice per device and the store colour
/// per company comes with the settings screen.)
class TashilColorController extends ValueNotifier<TashilColorSettings> {
  TashilColorController([super.value = const TashilColorSettings()]);

  /// Whether the system offers a wallpaper colour (Android 12+). Set by
  /// [TashilColorScope].
  bool get wallpaperAvailable => _wallpaper != null;
  Color? _wallpaper;

  /// The themes for the current settings.
  TashilThemes get themes => themesFor(value, wallpaper: _wallpaper);

  void update(TashilColorSettings Function(TashilColorSettings) change) =>
      value = change(value);

  static TashilColorController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ColorScopeInherited>()!
      .notifier!;
}

/// Put above [MaterialApp]: reads the wallpaper colour (official
/// `dynamic_color` package), builds the themes for the controller's
/// settings and rebuilds when they change.
class TashilColorScope extends StatelessWidget {
  const TashilColorScope({
    super.key,
    required this.controller,
    required this.builder,
  });

  final TashilColorController controller;
  final Widget Function(BuildContext, TashilThemes) builder;

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (light, dark) {
      controller._wallpaper = light?.primary;
      return _ColorScopeInherited(
        notifier: controller,
        child: ValueListenableBuilder(
          valueListenable: controller,
          builder: (c, _, _) => builder(c, controller.themes),
        ),
      );
    },
  );
}

class _ColorScopeInherited extends InheritedNotifier<TashilColorController> {
  const _ColorScopeInherited({required super.notifier, required super.child});
}

/// Content-based colour (M3): colours a contained area (a product's
/// details, a supplier's card) from an image in it, such as the product
/// photo. The rest of the app keeps its scheme. Uses Flutter's official
/// [ColorScheme.fromImageProvider] with the content algorithm, which keeps
/// the tones close to the image while staying accessible.
class ContentColorScope extends StatefulWidget {
  const ContentColorScope({
    super.key,
    required this.image,
    required this.child,
  });

  final ImageProvider image;
  final Widget child;

  @override
  State<ContentColorScope> createState() => _ContentColorScopeState();
}

class _ContentColorScopeState extends State<ContentColorScope> {
  ColorScheme? _scheme;
  Object? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ContentColorScope old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _load();
  }

  Future<void> _load() async {
    final brightness = Theme.of(context).brightness;
    final key = (widget.image, brightness);
    if (key == _key) return;
    _key = key;
    final scheme = await ColorScheme.fromImageProvider(
      provider: widget.image,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.content,
    );
    if (mounted && _key == key) setState(() => _scheme = scheme);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scheme;
    if (s == null) return widget.child;
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: s),
      child: widget.child,
    );
  }
}
