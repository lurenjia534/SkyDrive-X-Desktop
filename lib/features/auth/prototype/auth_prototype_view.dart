import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../auth_prototype_view_model.dart';
import 'auth_prototype_layout_config.dart';
import 'widgets/auth_background.dart';
import 'widgets/brand_widgets.dart';
import 'widgets/form_panel.dart';
import 'widgets/theme_toggle_button.dart';

/// 纯 UI 层：不依赖 Riverpod，不包含业务逻辑。
///
/// 约定：
/// - 导航、副作用监听放在页面容器里（`AuthPrototypePage`）。
/// - 本组件只做渲染与收集用户输入，并通过回调把事件抛给上层。
class AuthPrototypeView extends StatefulWidget {
  const AuthPrototypeView({
    super.key,
    required this.uiState,
    required this.onSignIn,
  });

  final AuthPrototypeUiState uiState;
  final Future<void> Function(String clientId) onSignIn;

  @override
  State<AuthPrototypeView> createState() => _AuthPrototypeViewState();
}

class _AuthPrototypeViewState extends State<AuthPrototypeView> {
  final TextEditingController _userIdController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    await widget.onSignIn(_userIdController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final width = MediaQuery.sizeOf(context).width;
    final config = AuthPrototypeLayoutConfig.fromWidth(
      width: width,
      breakpoints: theme.breakpoints,
    );

    final isAuthenticating = widget.uiState.isAuthenticating;
    final error = widget.uiState.error;

    return FScaffold(
      childPad: false,
      child: Stack(
        children: [
          Positioned.fill(child: AuthBackground(colors: colors)),
          Positioned(
            top: 16,
            right: 16,
            child: ThemeToggleButton(colors: colors),
          ),
          Center(
            child: SingleChildScrollView(
              padding: config.pagePadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: config.layout == AuthPrototypeLayout.mobile
                      ? 0
                      : config.cardMaxWidth,
                  maxWidth: config.cardMaxWidth,
                ),
                child: FCard.raw(
                  style: (style) => style.copyWith(
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(config.cardRadius),
                      border: Border.all(
                        color: colors.border.withValues(alpha: 0.5),
                      ),
                      boxShadow: config.layout == AuthPrototypeLayout.mobile
                          ? const []
                          : [
                              BoxShadow(
                                color: colors.barrier.withValues(alpha: 0.08),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              ),
                            ],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(config.cardRadius),
                    child: Padding(
                      padding: config.cardPadding,
                      child: config.isDesktop
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 45,
                                    child: BrandPanel(
                                      typography: typography,
                                      colors: colors,
                                      radius: config.cardRadius,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 55,
                                    child: AuthFormPanel(
                                      typography: typography,
                                      colors: colors,
                                      isAuthenticating: isAuthenticating,
                                      error: error,
                                      userIdController: _userIdController,
                                      onSignIn: _handleSignIn,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                BrandHeader(
                                  typography: typography,
                                  colors: colors,
                                ),
                                const SizedBox(height: 24),
                                AuthFormPanel(
                                  typography: typography,
                                  colors: colors,
                                  isAuthenticating: isAuthenticating,
                                  error: error,
                                  userIdController: _userIdController,
                                  onSignIn: _handleSignIn,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
