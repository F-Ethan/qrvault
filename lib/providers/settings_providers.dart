import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kThemeModeKey);
    state = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Nearby radius — stored as miles (1–25), default 1
// ---------------------------------------------------------------------------
const _kNearbyRadiusMilesKey = 'nearby_radius_miles';
const double nearbyRadiusDefault = 1.0;

final nearbyRadiusProvider = NotifierProvider<NearbyRadiusNotifier, double>(
  NearbyRadiusNotifier.new,
);

class NearbyRadiusNotifier extends Notifier<double> {
  @override
  double build() {
    _load();
    return nearbyRadiusDefault;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_kNearbyRadiusMilesKey);
    if (stored != null) state = stored;
  }

  Future<void> setRadius(double miles) async {
    state = miles;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kNearbyRadiusMilesKey, miles);
  }
}
