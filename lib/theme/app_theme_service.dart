import 'package:flutter/material.dart';
import 'package:skydrivex/src/rust/api/settings/theme.dart' as settings_api;

class AppThemeService {
  const AppThemeService();

  Future<bool> getFollowSystem() async {
    try {
      return await settings_api.getThemeFollowSystem();
    } catch (err) {
      throw ThemeSettingsUnavailable(err.toString());
    }
  }

  Future<bool> setFollowSystem(bool value) async {
    try {
      return await settings_api.setThemeFollowSystem(value: value);
    } catch (err) {
      throw ThemeSettingsUnavailable(err.toString());
    }
  }

  Future<ThemeMode> getManualMode() async {
    try {
      final raw = await settings_api.getThemeManualMode();
      return _parseThemeMode(raw);
    } catch (err) {
      throw ThemeSettingsUnavailable(err.toString());
    }
  }

  Future<ThemeMode> setManualMode(ThemeMode mode) async {
    try {
      final raw = await settings_api.setThemeManualMode(
        mode: _serializeThemeMode(mode),
      );
      return _parseThemeMode(raw);
    } catch (err) {
      throw ThemeSettingsUnavailable(err.toString());
    }
  }
}

ThemeMode _parseThemeMode(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'dark':
      return ThemeMode.dark;
    case 'light':
    default:
      return ThemeMode.light;
  }
}

String _serializeThemeMode(ThemeMode mode) {
  return mode == ThemeMode.dark ? 'dark' : 'light';
}

class ThemeSettingsUnavailable implements Exception {
  const ThemeSettingsUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ThemeSettingsUnavailable: $message';
}
