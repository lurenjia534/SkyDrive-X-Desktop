import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;
import 'package:skydrivex/src/rust/api/auth/refresh.dart' as auth_refresh;

typedef AuthTokens = auth_api.AuthTokens;

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
  const AuthState({this.tokens, this.error, this.isAuthenticating = false});

  final AuthTokens? tokens;
  final String? error;
  final bool isAuthenticating;

  /// 便捷的状态拷贝方法，可同时清空旧 token/错误。
  AuthState copyWith({
    bool? isAuthenticating,
    AuthTokens? tokens,
    String? error,
    bool clearTokens = false,
    bool clearError = false,
  }) {
    return AuthState(
      tokens: clearTokens ? null : (tokens ?? this.tokens),
      error: clearError ? null : (error ?? this.error),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    );
  }
}

/// 认证控制器：负责调用 Rust API、刷新 token，并根据情况更新状态。
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  void setValidationError(String message) {
    state = state.copyWith(
      error: message,
      clearTokens: true,
      isAuthenticating: false,
    );
  }

  /// 主动触发浏览器认证流程。
  Future<void> authenticate({
    required String clientId,
    required List<String> scopes,
  }) async {
    state = state.copyWith(
      isAuthenticating: true,
      clearError: true,
      clearTokens: true,
    );

    try {
      final tokens = await auth_api.authenticateViaBrowser(
        clientId: clientId,
        scopes: scopes,
      );
      state = state.copyWith(tokens: tokens, clearError: true);
    } catch (err) {
      state = state.copyWith(error: err.toString(), clearTokens: true);
    } finally {
      state = state.copyWith(isAuthenticating: false);
    }
  }

  /// UI 调用入口：先校验 Client ID，再走统一的 authenticate 逻辑。
  Future<void> authenticateWithClientId(String clientId) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) {
      setValidationError('Client ID is required.');
      return;
    }
    await authenticate(clientId: trimmed, scopes: kRequiredAuthScopes);
  }

  /// 尝试从本地持久化状态恢复 Session。
  Future<void> restoreSession() async {
    try {
      final persisted = await auth_api.loadPersistedAuthState();
      if (persisted == null) return;
    } catch (err) {
      state = state.copyWith(error: err.toString(), clearTokens: true);
      return;
    }
    await _refreshTokens(showLoading: true);
  }

  /// 静默刷新 token，返回是否刷新成功。
  Future<bool> refreshSilently() => _refreshTokens(showLoading: false);

  /// 通用刷新逻辑：可选显示 Loading，刷新失败时会清空 token。
  Future<bool> _refreshTokens({required bool showLoading}) async {
    if (showLoading) {
      state = state.copyWith(isAuthenticating: true, clearError: true);
    }
    try {
      final updatedState = await auth_refresh.refreshTokens();
      state = state.copyWith(tokens: updatedState.tokens, clearError: true);
      return true;
    } catch (err) {
      state = state.copyWith(error: err.toString(), clearTokens: true);
      return false;
    } finally {
      if (showLoading) {
        state = state.copyWith(isAuthenticating: false);
      }
    }
  }
}
