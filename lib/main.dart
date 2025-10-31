import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skydrivex/src/rust/api/auth.dart';
import 'package:skydrivex/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
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

class AuthPrototypePage extends StatefulWidget {
  const AuthPrototypePage({super.key});

  @override
  State<AuthPrototypePage> createState() => _AuthPrototypePageState();
}

class _AuthPrototypePageState extends State<AuthPrototypePage> {
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController(
    text: 'User.Read offline_access openid',
  );

  AuthTokens? _tokens;
  String? _error;
  bool _isAuthenticating = false;

  @override
  void dispose() {
    _clientIdController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  Future<void> _startAuthentication() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() {
        _error = 'Client ID is required.';
        _tokens = null;
      });
      return;
    }

    final scopeLine = _scopeController.text.trim();
    final scopes = scopeLine.isEmpty
        ? const <String>[]
        : scopeLine.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

    setState(() {
      _isAuthenticating = true;
      _error = null;
      _tokens = null;
    });

    try {
      final tokens = await authenticateViaBrowser(
        clientId: clientId,
        scopes: scopes,
      );
      if (!mounted) return;
      setState(() {
        _tokens = tokens;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                      if (_isAuthenticating) ...[
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
                        onPressed: _isAuthenticating
                            ? null
                            : _startAuthentication,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isAuthenticating
                            ? const SizedBox.shrink()
                            : const Icon(Icons.login_rounded),
                        label: _isAuthenticating
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
                      if (_error != null)
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
                                  _error!,
                                  style: TextStyle(color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_tokens != null) ...[
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
                          value: _tokens!.accessToken,
                        ),
                        if (_tokens!.refreshToken != null)
                          _buildTokenTile(
                            context,
                            label: '刷新令牌 (Refresh Token)',
                            value: _tokens!.refreshToken!,
                          ),
                        if (_tokens!.expiresIn != null)
                          _buildTokenTile(
                            context,
                            label: '有效期 (秒)',
                            value: _tokens!.expiresIn!.toString(),
                            isMonospace: false,
                          ),
                        if (_tokens!.scope != null)
                          _buildTokenTile(
                            context,
                            label: '授权范围',
                            value: _tokens!.scope!,
                            isMonospace: false,
                          ),
                        if (_tokens!.idToken != null)
                          _buildTokenTile(
                            context,
                            label: 'ID Token',
                            value: _tokens!.idToken!,
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
