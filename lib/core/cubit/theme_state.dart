part of 'theme_cubit.dart';

class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final Color seedColor;

  const ThemeState({
    this.themeMode = ThemeMode.light,
    this.seedColor = const Color(0xFF6750A4),
  });

  bool get isDarkMode => themeMode == ThemeMode.dark;

  ThemeState copyWith({ThemeMode? themeMode, Color? seedColor}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
    );
  }

  @override
  List<Object> get props => [themeMode, seedColor];
}
