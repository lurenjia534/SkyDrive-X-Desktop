import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/auth.dart';
import 'package:skydrivex/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: MyApp()));
}

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
      final tokens = await authenticateViaBrowser(
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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: const AuthPrototypePage(),
    );
  }
}

class AuthPrototypePage extends ConsumerStatefulWidget {
  const AuthPrototypePage({super.key});

  @override
  ConsumerState<AuthPrototypePage> createState() => _AuthPrototypePageState();
}

class _AuthPrototypePageState extends ConsumerState<AuthPrototypePage> {
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController(
    text: 'User.Read offline_access openid',
  );

  @override
  void dispose() {
    _clientIdController.dispose();
    _scopeController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authState = ref.watch(authControllerProvider);
    final tokens = authState.tokens;
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
                                  error!,
                                  style: TextStyle(color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (tokens != null) ...[
                        const SizedBox(height: 24),
                        Divider(color: colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          '令牌返回结果',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildTokenTile(
                          context,
                          label: '访问令牌 (Access Token)',
                          value: tokens.accessToken,
                        ),
                        if (tokens.refreshToken != null)
                          _buildTokenTile(
                            context,
                            label: '刷新令牌 (Refresh Token)',
                            value: tokens.refreshToken!,
                          ),
                        if (tokens.expiresIn != null)
                          _buildTokenTile(
                            context,
                            label: '有效期 (秒)',
                            value: tokens.expiresIn!.toString(),
                            isMonospace: false,
                          ),
                        if (tokens.scope != null)
                          _buildTokenTile(
                            context,
                            label: '授权范围',
                            value: tokens.scope!,
                            isMonospace: false,
                          ),
                        if (tokens.idToken != null)
                          _buildTokenTile(
                            context,
                            label: 'ID Token',
                            value: tokens.idToken!,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '仅用于验证流程的原型，请妥善保管令牌。',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
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

  Widget _buildTokenTile(
    BuildContext context, {
    required String label,
    required String value,
    bool isMonospace = true,
  }) {
    return _CollapsibleTokenTile(
      label: label,
      value: value,
      isMonospace: isMonospace,
    );
  }
}

class _CollapsibleTokenTile extends StatefulWidget {
  const _CollapsibleTokenTile({
    required this.label,
    required this.value,
    this.isMonospace = true,
  });

  final String label;
  final String value;
  final bool isMonospace;

  @override
  State<_CollapsibleTokenTile> createState() => _CollapsibleTokenTileState();
}

class _CollapsibleTokenTileState extends State<_CollapsibleTokenTile> {
  bool _expanded = false;

  String get _preview {
    const limit = 40;
    if (widget.value.length <= limit) return widget.value;
    return '${widget.value.substring(0, limit)}…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
        border: Border.all(color: colorScheme.outline.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: widget.isMonospace ? 'monospace' : null,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '复制到剪贴板',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.value),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${widget.label} 已复制'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 4),
                    child: SelectableText(
                      widget.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: widget.isMonospace ? 'monospace' : null,
                        height: 1.4,
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
