import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;
import 'package:skydrivex/src/rust/api/auth/refresh.dart' as auth_refresh;

typedef AuthTokens = auth_api.AuthTokens;
typedef AuthAccount = auth_api.AuthAccount;

const List<String> kRequiredAuthScopes = [
  'Files.ReadWrite',
  'User.Read',
  'offline_access',
  'openid',
];

/// Riverpod Provider：管理认证状态（token、错误、加载中）。
final authControllerProvider =
    NotifierProvider.autoDispose<AuthController, AuthState>(AuthController.new);

/// 认证状态：记录 token、错误信息与当前是否在认证中。
class AuthState {
  const AuthState({
    this.tokens,
    this.error,
    this.isAuthenticating = false,
    this.updatedAtMillis,
    this.expiresInSeconds,
    this.accounts = const [],
    this.isLoadingAccounts = false,
  });

  final AuthTokens? tokens;
  final String? error;
  final bool isAuthenticating;
  final int? updatedAtMillis;
  final int? expiresInSeconds;
  final List<AuthAccount> accounts;
  final bool isLoadingAccounts;

  /// 便捷的状态拷贝方法，可同时清空旧 token/错误。
  AuthState copyWith({
    bool? isAuthenticating,
    AuthTokens? tokens,
    String? error,
    int? updatedAtMillis,
    int? expiresInSeconds,
    List<AuthAccount>? accounts,
    bool? isLoadingAccounts,
    bool clearTokens = false,
    bool clearError = false,
  }) {
    return AuthState(
      tokens: clearTokens ? null : (tokens ?? this.tokens),
      error: clearError ? null : (error ?? this.error),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      updatedAtMillis: clearTokens ? null : (updatedAtMillis ?? this.updatedAtMillis),
      expiresInSeconds:
          clearTokens ? null : (expiresInSeconds ?? this.expiresInSeconds),
      accounts: accounts ?? this.accounts,
      isLoadingAccounts: isLoadingAccounts ?? this.isLoadingAccounts,
    );
  }
}

/// 认证控制器：负责调用 Rust API、刷新 token，并根据情况更新状态。
class AuthController extends Notifier<AuthState> {
  // 将刷新相关的状态更新合并到下一帧，避免同一帧内多次写 state。
  AuthState? _pendingRefreshState;
  bool _pendingRefreshScheduled = false;
  // 每次认证/刷新递增，用于丢弃过期的延迟更新。
  int _refreshGeneration = 0;
  Future<bool>? _refreshInFlight;
  bool _hasLoadedAccounts = false;

  @override
  AuthState build() {
    if (!_hasLoadedAccounts) {
      _hasLoadedAccounts = true;
      Future.microtask(_loadAccounts);
    }
    return const AuthState();
  }

  void setValidationError(String message) {
    state = state.copyWith(
      error: message,
      isAuthenticating: false,
    );
  }

  /// 主动触发浏览器认证流程。
  Future<bool> authenticate({
    required String clientId,
    required List<String> scopes,
  }) async {
    _refreshGeneration++;
    _pendingRefreshState = null;
    final preserveTokens = state.tokens != null;
    state = state.copyWith(
      isAuthenticating: true,
      clearError: true,
      clearTokens: !preserveTokens,
    );

    try {
      final tokens = await auth_api.authenticateViaBrowser(
        clientId: clientId,
        scopes: scopes,
      );
      if (!ref.mounted) return false;
      auth_api.StoredAuthState? persisted;
      try {
        persisted = await auth_api.loadPersistedAuthState();
      } catch (_) {
        persisted = null;
      }
      if (!ref.mounted) return false;
      final nextTokens = persisted?.tokens ?? tokens;
      state = state.copyWith(
        tokens: nextTokens,
        updatedAtMillis:
            persisted?.updatedAtMillis.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        expiresInSeconds: _expiresInSeconds(nextTokens),
        clearError: true,
      );
      unawaited(_loadAccounts());
      return true;
    } catch (err) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        error: err.toString(),
        clearTokens: !preserveTokens,
      );
      return false;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isAuthenticating: false);
      }
    }
  }

  /// UI 调用入口：先校验 Client ID，再走统一的 authenticate 逻辑。
  Future<bool> authenticateWithClientId(String clientId) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) {
      setValidationError('Client ID is required.');
      return false;
    }
    return authenticate(clientId: trimmed, scopes: kRequiredAuthScopes);
  }

  /// 尝试从本地持久化状态恢复 Session。
  Future<void> restoreSession() async {
    auth_api.StoredAuthState? persisted;
    try {
      persisted = await auth_api.loadPersistedAuthState();
    } catch (err) {
      if (!ref.mounted) return;
      state = state.copyWith(error: err.toString(), clearTokens: true);
      return;
    }
    if (!ref.mounted) return;
    if (persisted == null) return;
    _refreshGeneration++;
    _pendingRefreshState = null;
    _applyStoredState(persisted);
    unawaited(_loadAccounts());
  }

  Future<void> refreshAccounts() => _loadAccounts();

  Future<bool> setActiveAccount(String accountId) async {
    state = state.copyWith(isAuthenticating: true, clearError: true);
    try {
      final nextState = await auth_api.setActiveAuthAccount(
        accountId: accountId,
      );
      if (!ref.mounted) return false;
      _refreshGeneration++;
      _pendingRefreshState = null;
      _applyStoredState(nextState);
      unawaited(_loadAccounts());
      return true;
    } catch (err) {
      if (!ref.mounted) return false;
      state = state.copyWith(error: err.toString(), isAuthenticating: false);
      return false;
    }
  }

  Future<bool> removeAccount(String accountId, {required bool wasActive}) async {
    state = state.copyWith(isAuthenticating: true, clearError: true);
    try {
      final nextState = await auth_api.removeAuthAccount(
        accountId: accountId,
      );
      if (!ref.mounted) return false;
      if (nextState != null) {
        _refreshGeneration++;
        _pendingRefreshState = null;
        _applyStoredState(nextState);
      } else if (wasActive) {
        state = state.copyWith(clearTokens: true, isAuthenticating: false);
      } else {
        state = state.copyWith(isAuthenticating: false);
      }
      await _loadAccounts();
      return true;
    } catch (err) {
      if (!ref.mounted) return false;
      state = state.copyWith(error: err.toString(), isAuthenticating: false);
      return false;
    }
  }

  /// 静默刷新 token，返回是否刷新成功。
  Future<bool> refreshSilently() => _refreshTokens(showLoading: false);

  /// 通用刷新逻辑：可选显示 Loading，刷新失败时会清空 token。
  Future<bool> _refreshTokens({required bool showLoading}) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefreshTokens(showLoading: showLoading);
    _refreshInFlight = future;
    future.whenComplete(() {
      if (_refreshInFlight == future) {
        _refreshInFlight = null;
      }
    });
    return future;
  }

  Future<bool> _doRefreshTokens({required bool showLoading}) async {
    final refreshGeneration = ++_refreshGeneration;
    if (showLoading) {
      state = state.copyWith(isAuthenticating: true, clearError: true);
    }
    try {
      final updatedState = await auth_refresh.refreshTokens();
      if (!ref.mounted) return false;
      final nextState = state.copyWith(
        tokens: updatedState.tokens,
        updatedAtMillis: updatedState.updatedAtMillis.toInt(),
        expiresInSeconds: _expiresInSeconds(updatedState.tokens),
        clearError: true,
        isAuthenticating: showLoading ? false : state.isAuthenticating,
      );
      if (showLoading) {
        // 延迟到下一帧提交最终状态，避免触发 Riverpod Scheduler
        // debugNotifyDidBuild 的同帧多次重建保护。
        _scheduleRefreshState(nextState, refreshGeneration);
      } else {
        state = nextState;
      }
      return true;
    } catch (err) {
      if (!ref.mounted) return false;
      final message = err.toString();
      final shouldClear = _shouldClearTokensOnRefreshError(message);
      final nextState = state.copyWith(
        error: message,
        clearTokens: shouldClear,
        isAuthenticating: showLoading ? false : state.isAuthenticating,
      );
      if (showLoading) {
        // 延迟错误状态，避免恢复流程中同帧连写导致重建冲突。
        _scheduleRefreshState(nextState, refreshGeneration);
      } else {
        state = nextState;
      }
      return false;
    }
  }

  Future<void> _loadAccounts() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoadingAccounts: true);
    try {
      final accounts = await auth_api.listAuthAccounts();
      if (!ref.mounted) return;
      state = state.copyWith(accounts: accounts, isLoadingAccounts: false);
    } catch (err) {
      if (!ref.mounted) return;
      state = state.copyWith(error: err.toString(), isLoadingAccounts: false);
    }
  }

  void _applyStoredState(auth_api.StoredAuthState persisted) {
    state = state.copyWith(
      tokens: persisted.tokens,
      updatedAtMillis: persisted.updatedAtMillis.toInt(),
      expiresInSeconds: _expiresInSeconds(persisted.tokens),
      clearError: true,
      isAuthenticating: false,
    );
  }

  int? _expiresInSeconds(AuthTokens tokens) {
    final expiresIn = tokens.expiresIn;
    if (expiresIn == null) return null;
    try {
      return expiresIn.toInt();
    } catch (_) {
      return null;
    }
  }

  bool _shouldClearTokensOnRefreshError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('no refresh token')) return true;
    if (lower.contains('no persisted authentication state')) return true;
    if (lower.contains('interactive authentication required')) return true;
    if (lower.contains('invalid_grant')) return true;
    if (lower.contains('interaction_required')) return true;
    if (lower.contains('login_required')) return true;
    if (lower.contains('consent_required')) return true;
    if (lower.contains('aadsts')) return true;

    const marker = 'token endpoint returned http ';
    final index = lower.indexOf(marker);
    if (index != -1) {
      final tail = lower.substring(index + marker.length).trimLeft();
      final code = int.tryParse(tail.split(' ').first);
      if (code != null && code >= 400 && code < 500 && code != 429) {
        return true;
      }
    }
    return false;
  }

  void _scheduleRefreshState(AuthState nextState, int refreshGeneration) {
    _pendingRefreshState = nextState;
    if (_pendingRefreshScheduled) return;
    _pendingRefreshScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingRefreshScheduled = false;
      if (!ref.mounted || refreshGeneration != _refreshGeneration) return;
      final pending = _pendingRefreshState;
      _pendingRefreshState = null;
      if (pending != null) {
        state = pending;
      }
    });
  }
}
