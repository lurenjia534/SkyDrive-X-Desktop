import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme_service.dart';

@immutable
class AppThemeState {
  const AppThemeState({
    required this.followSystem,
    required this.manualMode,
  });

  final bool followSystem;
  final ThemeMode manualMode;

  static const defaults = AppThemeState(
    followSystem: true,
    manualMode: ThemeMode.light,
  );

  ThemeMode get themeMode => followSystem ? ThemeMode.system : manualMode;

  AppThemeState copyWith({
    bool? followSystem,
    ThemeMode? manualMode,
  }) {
    return AppThemeState(
      followSystem: followSystem ?? this.followSystem,
      manualMode: manualMode ?? this.manualMode,
    );
  }
}

final appThemeProvider =
    AsyncNotifierProvider<AppThemeController, AppThemeState>(
  AppThemeController.new,
);

class AppThemeController extends AsyncNotifier<AppThemeState> {
  late final AppThemeService _service;

  @override
  Future<AppThemeState> build() async {
    _service = const AppThemeService();
    final followSystem = await _service.getFollowSystem();
    final manualMode = await _service.getManualMode();
    return AppThemeState(
      followSystem: followSystem,
      manualMode: manualMode,
    );
  }

  AppThemeState _fallbackState() {
    return state.value ?? AppThemeState.defaults;
  }

  Future<void> setFollowSystem(bool followSystem) async {
    final previous = _fallbackState();
    final next = previous.copyWith(followSystem: followSystem);
    state = AsyncValue.data(next);
    try {
      await _service.setFollowSystem(followSystem);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      state = AsyncValue.data(previous);
      rethrow;
    }
  }

  Future<void> setManualMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      return;
    }
    final previous = _fallbackState();
    final next = previous.copyWith(
      followSystem: false,
      manualMode: mode,
    );
    state = AsyncValue.data(next);
    try {
      await _service.setFollowSystem(false);
      await _service.setManualMode(mode);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      state = AsyncValue.data(previous);
      rethrow;
    }
  }

  Future<void> toggleManualMode() async {
    final previous = _fallbackState();
    final nextMode = previous.manualMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    final next = previous.copyWith(
      followSystem: false,
      manualMode: nextMode,
    );
    state = AsyncValue.data(next);
    try {
      await _service.setFollowSystem(false);
      await _service.setManualMode(nextMode);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      state = AsyncValue.data(previous);
      rethrow;
    }
  }
}
