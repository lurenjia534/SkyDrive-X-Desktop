import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import '../drive/drive_workspace_page.dart';

class AuthPrototypePage extends ConsumerStatefulWidget {
  const AuthPrototypePage({super.key});

  @override
  ConsumerState<AuthPrototypePage> createState() => _AuthPrototypePageState();
}

class _AuthPrototypePageState extends ConsumerState<AuthPrototypePage> {
  static const _refreshInterval = Duration(minutes: 50);
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController(
    text: 'User.Read offline_access openid',
  );
  Timer? _refreshTimer;
  ProviderSubscription<AuthState>? _authSubscription;
  bool _navigatedToDrive = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual<AuthState>(authControllerProvider, (
      previous,
      next,
    ) {
      final hadTokens = previous?.tokens != null;
      final hasTokens = next.tokens != null;
      if (!hadTokens && hasTokens) {
        _startRefreshTimer();
        _navigateToDrive();
      } else if (hadTokens && !hasTokens) {
        _stopRefreshTimer();
        _navigatedToDrive = false;
      }
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptRestoreSession();
    });
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _authSubscription?.close();
    _clientIdController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  Future<void> _attemptRestoreSession() async {
    final controller = ref.read(authControllerProvider.notifier);
    await controller.restoreSession();
  }

  Future<void> _startAuthentication() async {
    final clientId = _clientIdController.text.trim();
    final controller = ref.read(authControllerProvider.notifier);
    if (clientId.isEmpty) {
      controller.setValidationError('Client ID is required.');
      return;
    }

    final scopeLine = _scopeController.text.trim();
    final scopes = scopeLine.isEmpty
        ? const <String>[]
        : scopeLine.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

    await controller.authenticate(clientId: clientId, scopes: scopes);
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      ref.read(authControllerProvider.notifier).refreshSilently();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _navigateToDrive() async {
    if (_navigatedToDrive || !mounted) return;
    final tokens = ref.read(authControllerProvider).tokens;
    if (tokens == null) return;
    _navigatedToDrive = true;
    await Navigator.of(context).pushReplacement(
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
    final error = authState.error;
    final isAuthenticating = authState.isAuthenticating;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.14),
              colorScheme.secondaryContainer.withOpacity(0.12),
              colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: colorScheme.primary.withOpacity(
                              0.12,
                            ),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '使用浏览器完成授权，以便 Skydrivex 同步 OneDrive 数据。',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                      TextField(
                        controller: _scopeController,
                        decoration: InputDecoration(
                          labelText: '请求的作用域 (空格分隔)',
                          helperText: '默认包含 User.Read、offline_access、openid',
                          prefixIcon: const Icon(Icons.lock_open_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: isAuthenticating
                            ? null
                            : _startAuthentication,
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
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: colorScheme.errorContainer,
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  error,
                                  style: TextStyle(color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
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
