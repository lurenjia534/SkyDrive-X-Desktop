import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

final authSessionCoordinatorProvider =
    NotifierProvider.autoDispose<AuthSessionCoordinator, AuthSessionState>(
  AuthSessionCoordinator.new,
);

class AuthSessionState {
  const AuthSessionState({this.shouldNavigateToDrive = false});

  final bool shouldNavigateToDrive;

  AuthSessionState copyWith({bool? shouldNavigateToDrive}) {
    return AuthSessionState(
      shouldNavigateToDrive: shouldNavigateToDrive ?? this.shouldNavigateToDrive,
    );
  }
}

class AuthSessionCoordinator extends Notifier<AuthSessionState> {
  static const _refreshInterval = Duration(minutes: 50);
  Timer? _refreshTimer;

  @override
  AuthSessionState build() {
    ref.listen<AuthState>(
      authControllerProvider,
      _handleAuthStateChange,
      fireImmediately: true,
    );
    ref.onDispose(() {
      _refreshTimer?.cancel();
    });
    return const AuthSessionState();
  }

  Future<void> attemptRestoreSession() {
    return ref.read(authControllerProvider.notifier).restoreSession();
  }

  Future<void> authenticateWithClientId(String clientId) {
    return ref
        .read(authControllerProvider.notifier)
        .authenticateWithClientId(clientId);
  }

  Future<bool> refreshSilently() {
    return ref.read(authControllerProvider.notifier).refreshSilently();
  }

  void clearNavigationIntent() {
    if (state.shouldNavigateToDrive) {
      state = state.copyWith(shouldNavigateToDrive: false);
    }
  }

  void _handleAuthStateChange(AuthState? previous, AuthState next) {
    final hadTokens = previous?.tokens != null;
    final hasTokens = next.tokens != null;
    if (!hadTokens && hasTokens) {
      _startRefreshTimer();
      state = state.copyWith(shouldNavigateToDrive: true);
    } else if (hadTokens && !hasTokens) {
      _stopRefreshTimer();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      refreshSilently();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
