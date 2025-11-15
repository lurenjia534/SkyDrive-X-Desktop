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

final authControllerProvider =
    NotifierProvider.autoDispose<AuthController, AuthState>(AuthController.new);

class AuthState {
  const AuthState({this.tokens, this.error, this.isAuthenticating = false});

  final AuthTokens? tokens;
  final String? error;
  final bool isAuthenticating;

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

  Future<void> authenticateWithClientId(String clientId) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) {
      setValidationError('Client ID is required.');
      return;
    }
    await authenticate(clientId: trimmed, scopes: kRequiredAuthScopes);
  }

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

  Future<bool> refreshSilently() => _refreshTokens(showLoading: false);

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
