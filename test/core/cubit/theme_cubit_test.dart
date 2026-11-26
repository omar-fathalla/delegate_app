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

  test('dark scheme uses the approved M3 values', () {
    final s = AppTheme.darkTheme(const Color(0xFF6750A4)).colorScheme;
    expect(s.primary, const Color(0xFFCFBCFF));
    expect(s.primaryContainer, const Color(0xFF4F378A));
    expect(s.surface, const Color(0xFF141313));
    expect(s.surfaceContainer, const Color(0xFF201F20));
    expect(s.surfaceContainerHigh, const Color(0xFF2B2A2A));
    expect(s.error, const Color(0xFFFFB4AB));
  });
}
