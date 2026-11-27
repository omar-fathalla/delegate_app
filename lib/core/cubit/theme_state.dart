part of 'theme_cubit.dart';

class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final Color seedColor;

  /// M3 contrast level (playground «التباين», TAS-387).
  final TashilContrast contrast;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color(0xFF6750A4),
    this.contrast = TashilContrast.standard,
  });

  bool get isDarkMode => themeMode == ThemeMode.dark;

  ThemeState copyWith({
    ThemeMode? themeMode,
    Color? seedColor,
    TashilContrast? contrast,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      contrast: contrast ?? this.contrast,
    );
  }

  @override
  List<Object> get props => [themeMode, seedColor, contrast];
}
