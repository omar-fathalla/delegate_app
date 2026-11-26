import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('defaults to System on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ThemeCubit(await SharedPreferences.getInstance());
    expect(c.state.themeMode, ThemeMode.system);
  });

  test('keeps a saved choice and persists changes', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
    final prefs = await SharedPreferences.getInstance();
    final c = ThemeCubit(prefs);
    expect(c.state.themeMode, ThemeMode.light);
    c.setThemeMode(ThemeMode.dark);
    expect(prefs.getString('app_theme_mode'), 'dark');
    expect(ThemeCubit(prefs).state.themeMode, ThemeMode.dark);
  });

  // TAS-348 (user decision 2026-11-26): the dark scheme is generated from the
  // seed like every other role (m3-kit design-system.md, Colour: "never
  // hand-pick tones"). The pinned values of 47d05fb0 are gone.
  test('dark scheme is generated from the seed', () {
    const seed = Color(0xFF6750A4);
    final s = AppTheme.darkTheme(seed).colorScheme;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    expect(s.brightness, Brightness.dark);
    expect(s.primary, generated.primary);
    expect(s.primaryContainer, generated.primaryContainer);
    expect(s.surface, generated.surface);
    expect(s.surfaceContainer, generated.surfaceContainer);
    expect(s.surfaceContainerHigh, generated.surfaceContainerHigh);
    expect(s.error, generated.error);
  });
}
