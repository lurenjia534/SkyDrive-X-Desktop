import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_session_coordinator.dart';

/// `AuthPrototypePage` 的页面级 ViewModel。
///
/// 目标：
/// - 解耦页面与认证/副作用协调逻辑：页面只关心 UI 状态与事件回调。
/// - 将 `AuthController` + `AuthSessionCoordinator` 组合为页面所需的最小状态。
/// - 负责页面首次可用时触发一次 Session 恢复（避免页面里写生命周期副作用）。
final authPrototypeViewModelProvider =
    NotifierProvider.autoDispose<AuthPrototypeViewModel, AuthPrototypeUiState>(
      AuthPrototypeViewModel.new,
    );

/// 页面渲染所需的精简状态。
class AuthPrototypeUiState {
  const AuthPrototypeUiState({
    this.isAuthenticating = false,
    this.error,
    this.shouldNavigateToDrive = false,
  });

  /// 是否正在认证/刷新 token。
  final bool isAuthenticating;

  /// 可展示给用户的错误信息。
  final String? error;

  /// 一次性导航意图：当 token 准备好时，由协调器置为 `true`。
  /// 页面完成导航后需调用 [AuthPrototypeViewModel.clearNavigationIntent] 重置。
  final bool shouldNavigateToDrive;
}

class AuthPrototypeViewModel extends Notifier<AuthPrototypeUiState> {
  /// 保证 `attemptRestoreSession()` 仅在当前 provider 生命周期内触发一次。
  ///
  /// 使用 `autoDispose` 时，当页面退出后 provider 会被释放；下次进入页面会重新恢复一次。
  bool _hasAttemptedRestore = false;

  @override
  AuthPrototypeUiState build() {
    final authState = ref.watch(authControllerProvider);
    final sessionState = ref.watch(authSessionCoordinatorProvider);

    if (!_hasAttemptedRestore) {
      _hasAttemptedRestore = true;
      // 避免在 build 同步阶段触发副作用/状态写入，使用 microtask 延后执行。
      Future.microtask(() {
        ref
            .read(authSessionCoordinatorProvider.notifier)
            .attemptRestoreSession();
      });
    }

    return AuthPrototypeUiState(
      isAuthenticating: authState.isAuthenticating,
      error: authState.error,
      shouldNavigateToDrive: sessionState.shouldNavigateToDrive,
    );
  }

  /// 触发登录流程（由 UI 提交 Client ID 调用）。
  Future<void> signInWithClientId(String clientId) {
    return ref
        .read(authSessionCoordinatorProvider.notifier)
        .authenticateWithClientId(clientId);
  }

  /// 页面完成导航后清理一次性导航意图，避免重复跳转。
  void clearNavigationIntent() {
    ref.read(authSessionCoordinatorProvider.notifier).clearNavigationIntent();
  }
}
