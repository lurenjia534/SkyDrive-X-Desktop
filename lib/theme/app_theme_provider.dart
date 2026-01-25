import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AppThemeState {
  const AppThemeState({
    required this.followSystem,
    required this.manualMode,
  });

  final bool followSystem;
  final ThemeMode manualMode;

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

final appThemeProvider = NotifierProvider<AppThemeController, AppThemeState>(
  AppThemeController.new,
);

class AppThemeController extends Notifier<AppThemeState> {
  @override
  AppThemeState build() {
    return const AppThemeState(
      followSystem: true,
      manualMode: ThemeMode.light,
    );
  }

  void setFollowSystem(bool followSystem) {
    state = state.copyWith(followSystem: followSystem);
  }

  void setManualMode(ThemeMode mode) {
    if (mode == ThemeMode.system) {
      return;
    }
    state = state.copyWith(
      followSystem: false,
      manualMode: mode,
    );
  }

  void toggleManualMode() {
    final nextMode = state.manualMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    state = state.copyWith(
      followSystem: false,
      manualMode: nextMode,
    );
  }
}
