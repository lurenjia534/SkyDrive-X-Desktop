import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

/// 为认证页面提供副作用协调能力（定时刷新、导航信号等）。
final authSessionCoordinatorProvider =
    NotifierProvider.autoDispose<AuthSessionCoordinator, AuthSessionState>(
  AuthSessionCoordinator.new,
);

/// 协调器向 UI 暴露的简单状态。
class AuthSessionState {
  const AuthSessionState({this.shouldNavigateToDrive = false});

  final bool shouldNavigateToDrive;

  AuthSessionState copyWith({bool? shouldNavigateToDrive}) {
    return AuthSessionState(
      shouldNavigateToDrive: shouldNavigateToDrive ?? this.shouldNavigateToDrive,
    );
  }
}

/// 监听 AuthController 状态，触发刷新与导航副作用。
class AuthSessionCoordinator extends Notifier<AuthSessionState> {
  static const _refreshInterval = Duration(minutes: 50);
  Timer? _refreshTimer;

  @override
  AuthSessionState build() {
    // 监听认证状态，从而得知 token 何时生成/失效。
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

  /// 触发恢复 Session（供页面初始化调用）。
  Future<void> attemptRestoreSession() {
    return ref.read(authControllerProvider.notifier).restoreSession();
  }

  /// UI 提交 Client ID 时调用，委托给 AuthController。
  Future<void> authenticateWithClientId(String clientId) {
    return ref
        .read(authControllerProvider.notifier)
        .authenticateWithClientId(clientId);
  }

  /// 外部可手动触发一次静默刷新。
  Future<bool> refreshSilently() {
    return ref.read(authControllerProvider.notifier).refreshSilently();
  }

  /// 页面完成导航后，调用此方法重置状态。
  void clearNavigationIntent() {
    if (state.shouldNavigateToDrive) {
      state = state.copyWith(shouldNavigateToDrive: false);
    }
  }

  /// 根据 token 是否存在，决定是否触发刷新/导航。
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

  /// 启动静默刷新定时器，防止重复创建。
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      refreshSilently();
    });
  }

  /// 停止定时器并释放资源。
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
