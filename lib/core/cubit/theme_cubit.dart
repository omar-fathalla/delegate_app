import 'package:delegate_app/config/theme/color_schemes.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_state.dart';

/// Cubit to manage the application's theme mode (System, Light, Dark) and seed color.
class ThemeCubit extends Cubit<ThemeState> {
  static const _kThemeKey = 'app_theme_mode';
  static const _kSeedColorKey = 'app_seed_color';
  final SharedPreferences _prefs;

  ThemeCubit(this._prefs) : super(const ThemeState()) {
    _loadTheme();
  }

  void _loadTheme() {
    final savedTheme = _prefs.getString(_kThemeKey);
    ThemeMode mode = ThemeMode.system;
    if (savedTheme != null) {
      mode = ThemeMode.values.firstWhere(
        (e) => e.name == savedTheme,
        orElse: () => ThemeMode.system,
      );
    }

    final savedColor = _prefs.getInt(_kSeedColorKey);
    Color color = AppColorSchemes.seedColors[0];
    if (savedColor != null) {
      color = Color(savedColor);
    }

    emit(state.copyWith(themeMode: mode, seedColor: color));
  }

  void toggleTheme() {
    final newMode = state.isDarkMode ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(newMode);
  }

  void setThemeMode(ThemeMode mode) {
    if (state.themeMode == mode) return;
    _prefs.setString(_kThemeKey, mode.name);
    emit(state.copyWith(themeMode: mode));
  }

  void setSeedColor(Color color) {
    if (state.seedColor == color) return;
    // ignore: deprecated_member_use
    _prefs.setInt(_kSeedColorKey, color.value);
    emit(state.copyWith(seedColor: color));
  }
}
