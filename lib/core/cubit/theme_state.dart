part of 'theme_cubit.dart';

class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final Color seedColor;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color.fromARGB(255, 209, 169, 50),
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
