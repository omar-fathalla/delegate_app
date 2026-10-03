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
  static const _kMigratedPurpleKey = 'migrated_to_purple_default_v3';
  static const _kMigratedLightKey = 'migrated_to_light_default_v1';
  final SharedPreferences _prefs;

  ThemeCubit(this._prefs) : super(const ThemeState()) {
    _loadTheme();
  }

  void _loadTheme() {
    final savedTheme = _prefs.getString(_kThemeKey);
    final isMigratedLight = _prefs.getBool(_kMigratedLightKey) ?? false;
    ThemeMode mode = ThemeMode.light;

    if (!isMigratedLight) {
      _prefs.setBool(_kMigratedLightKey, true);
      if (savedTheme == null || savedTheme == ThemeMode.system.name) {
        _prefs.setString(_kThemeKey, ThemeMode.light.name);
        mode = ThemeMode.light;
      } else {
        mode = ThemeMode.values.firstWhere(
          (e) => e.name == savedTheme,
          orElse: () => ThemeMode.light,
        );
      }
    } else if (savedTheme != null) {
      mode = ThemeMode.values.firstWhere(
        (e) => e.name == savedTheme,
        orElse: () => ThemeMode.light,
      );
    }

    // Default primary color is Material You Deep Purple
    Color color = AppColorSchemes.seedColors[0];

    final isMigrated = _prefs.getBool(_kMigratedPurpleKey) ?? false;
    if (!isMigrated) {
      // One-time automatic migration: Ensure all existing and new devices start with Deep Purple as primary default
      _prefs.setBool(_kMigratedPurpleKey, true);
      // ignore: deprecated_member_use
      _prefs.setInt(_kSeedColorKey, color.value);
    } else {
      final rawSavedColor = _prefs.getInt(_kSeedColorKey);
      if (rawSavedColor != null) {
        final savedColor = rawSavedColor & 0xFFFFFFFF;
        color = Color(savedColor);
      }
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
