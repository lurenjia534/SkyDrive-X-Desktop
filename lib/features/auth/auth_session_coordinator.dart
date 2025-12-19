import 'dart:async';

import 'package:flutter/scheduler.dart';
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
  bool _hasAttemptedRestore = false;
  // 延迟状态提交到下一帧，避免触发 Riverpod 同帧多次重建保护。
  AuthSessionState? _pendingState;
  bool _pendingStateScheduled = false;

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
    if (!_hasAttemptedRestore) {
      _hasAttemptedRestore = true;
      // 首帧后再恢复 Session，保持 build 纯净，避免触发 Scheduler 的同帧重建检查。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!ref.mounted) return;
        unawaited(attemptRestoreSession());
      });
    }
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
      // 导航意图延迟提交，避免同一帧内多次写入导致重建冲突。
      _scheduleState(state.copyWith(shouldNavigateToDrive: false));
    }
  }

  /// 根据 token 是否存在，决定是否触发刷新/导航。
  void _handleAuthStateChange(AuthState? previous, AuthState next) {
    final hadTokens = previous?.tokens != null;
    final hasTokens = next.tokens != null;
    if (!hadTokens && hasTokens) {
      _startRefreshTimer();
      // 导航信号延迟提交，避免同帧内多次重建。
      _scheduleState(state.copyWith(shouldNavigateToDrive: true));
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

  void _scheduleState(AuthSessionState nextState) {
    _pendingState = nextState;
    if (_pendingStateScheduled) return;
    _pendingStateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingStateScheduled = false;
      if (!ref.mounted) return;
      final pending = _pendingState;
      _pendingState = null;
      if (pending != null) {
        state = pending;
      }
    });
  }
}
