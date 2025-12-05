import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drive/drive_workspace_page.dart';
import 'auth_controller.dart';
import 'auth_session_coordinator.dart';

class AuthPrototypePage extends ConsumerStatefulWidget {
  const AuthPrototypePage({super.key});

  @override
  ConsumerState<AuthPrototypePage> createState() => _AuthPrototypePageState();
}

class _AuthPrototypePageState extends ConsumerState<AuthPrototypePage> {
  final TextEditingController _clientIdController = TextEditingController();
  bool _isNavigating = false;
  ProviderSubscription<AuthSessionState>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authSessionCoordinatorProvider.notifier).attemptRestoreSession();
    });
    _sessionSubscription = ref.listenManual<AuthSessionState>(
      authSessionCoordinatorProvider,
      (prev, next) {
        if (!mounted) return;
        if (next.shouldNavigateToDrive && !_isNavigating) {
          _isNavigating = true;
          _navigateToDrive();
          ref
              .read(authSessionCoordinatorProvider.notifier)
              .clearNavigationIntent();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _sessionSubscription?.close();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    await ref
        .read(authSessionCoordinatorProvider.notifier)
        .authenticateWithClientId(_clientIdController.text);
  }

  void _navigateToDrive() {
    final tokens = ref.read(authControllerProvider).tokens;
    if (tokens == null || !mounted) {
      _isNavigating = false;
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriveWorkspacePage(
          authPageBuilder: (_) => const AuthPrototypePage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authState = ref.watch(authControllerProvider);
    final isAuthenticating = authState.isAuthenticating;
    final error = authState.error;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.14),
              colorScheme.secondaryContainer.withValues(alpha: 0.12),
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AuthHeader(colorScheme: colorScheme),
                      if (isAuthenticating) ...[
                        const SizedBox(height: 24),
                        const LinearProgressIndicator(minHeight: 3),
                      ],
                      const SizedBox(height: 28),
                      TextField(
                        controller: _clientIdController,
                        decoration: InputDecoration(
                          labelText: 'Azure 应用程序 (Client) ID',
                          hintText: '00000000-0000-0000-0000-000000000000',
                          prefixIcon: const Icon(Icons.key_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _ScopeInfoCard(),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: isAuthenticating ? null : _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: isAuthenticating
                            ? const SizedBox.shrink()
                            : const Icon(Icons.login_rounded),
                        label: isAuthenticating
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                '使用 Microsoft 登录',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                      const SizedBox(height: 20),
                      if (error != null)
                        _ErrorBanner(message: error, colorScheme: colorScheme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.cloud_sync_rounded,
            size: 32,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '连接 Microsoft 账户',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '使用浏览器完成授权，以便 Skydrivex 同步 OneDrive 数据。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.colorScheme});

  final String message;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.errorContainer,
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _ScopeInfoCard extends StatelessWidget {
  const _ScopeInfoCard();

  static const Map<String, String> _descriptions = {
    'Files.ReadWrite': '访问并管理 OneDrive 中的所有文件。',
    'User.Read': '读取基础个人资料并完成登录。',
    'offline_access': '获取刷新令牌以保持会话有效。',
    'openid': '遵循 OpenID Connect 协议所需的标识作用域。',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      colors: [
        colorScheme.primaryContainer.withValues(alpha: 0.4),
        colorScheme.secondaryContainer.withValues(alpha: 0.3),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_open_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '请求的作用域',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...kRequiredAuthScopes.map(
              (scope) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scope,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _descriptions[scope] ?? '',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
