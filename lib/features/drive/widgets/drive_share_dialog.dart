import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/drive_share_provider.dart';
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

class DriveShareDialog extends ConsumerStatefulWidget {
  const DriveShareDialog({super.key});

  @override
  ConsumerState<DriveShareDialog> createState() => _DriveShareDialogState();
}

class _DriveShareDialogState extends ConsumerState<DriveShareDialog> {
  drive_models.LinkType _linkType = drive_models.LinkType.view;
  drive_models.LinkScope _scope = drive_models.LinkScope.anonymous;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _recipientsController = TextEditingController();
  bool _retainInherited = true;
  bool _creating = false;
  String? _resultUrl;

  @override
  void dispose() {
    _passwordController.dispose();
    _recipientsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capsAsync = ref.watch(shareCapabilitiesProvider);
    final item = ref.watch(shareTargetItemProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget content;
    if (capsAsync.isLoading) {
      content = const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (capsAsync.hasError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('无法获取分享能力', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            capsAsync.error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ref.refresh(shareCapabilitiesProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ),
        ],
      );
    } else {
      final caps = capsAsync.value!;
      final canEmbed = caps.canEmbedLink;
      final canOrg = caps.canOrgScopeLink;
      final canPassword = caps.canPassword;
      final scopeOptions = <_ScopeOption>[
        _ScopeOption(
          label: '任何知道链接的人',
          scope: drive_models.LinkScope.anonymous,
          enabled: true,
          icon: Icons.public_rounded,
        ),
        _ScopeOption(
          label: '仅组织内人员',
          scope: drive_models.LinkScope.organization,
          enabled: canOrg,
          icon: Icons.apartment_rounded,
        ),
        _ScopeOption(
          label: '指定人员',
          scope: drive_models.LinkScope.users,
          enabled: true,
          icon: Icons.people_alt_rounded,
        ),
      ];
      final typeOptions = <_TypeOption>[
        _TypeOption(
          label: '仅查看',
          type: drive_models.LinkType.view,
          icon: Icons.visibility_rounded,
          enabled: true,
        ),
        _TypeOption(
          label: '可编辑',
          type: drive_models.LinkType.edit,
          icon: Icons.edit_rounded,
          enabled: true,
        ),
        _TypeOption(
          label: '嵌入',
          type: drive_models.LinkType.embed,
          icon: Icons.code_rounded,
          enabled: canEmbed,
        ),
      ];

      final passwordField = canPassword
          ? TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '密码（可选，仅个人版）',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              obscureText: true,
            )
          : null;

      final recipientsField = _scope == drive_models.LinkScope.users
          ? TextField(
              controller: _recipientsController,
              decoration: const InputDecoration(
                labelText: '指定人员邮箱（逗号分隔）',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            )
          : null;

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('分享 “${item.name}”', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('链接类型', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: typeOptions
                .map(
                  (opt) => ChoiceChip(
                    label: Text(opt.label),
                    avatar: Icon(opt.icon, size: 18),
                    selected: _linkType == opt.type,
                    onSelected: opt.enabled
                        ? (_) => setState(() => _linkType = opt.type)
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text('访问范围', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: scopeOptions
                .map(
                  (opt) => ChoiceChip(
                    label: Text(opt.label),
                    avatar: Icon(opt.icon, size: 18),
                    selected: _scope == opt.scope,
                    onSelected: opt.enabled
                        ? (_) => setState(() => _scope = opt.scope)
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _retainInherited,
                onChanged: (v) => setState(() => _retainInherited = v ?? true),
              ),
              const Expanded(child: Text('保留继承的权限（避免覆盖父级设置）')),
            ],
          ),
          if (passwordField != null) ...[
            const SizedBox(height: 8),
            passwordField,
          ],
          if (recipientsField != null) ...[
            const SizedBox(height: 8),
            recipientsField,
          ],
          const SizedBox(height: 16),
          if (_resultUrl != null)
            _ShareResult(
              url: _resultUrl!,
              onCopy: () => _copyAndNotify(context, _resultUrl!),
            ),
        ],
      );
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.share_outlined),
          const SizedBox(width: 8),
          Text('创建分享链接', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _creating || capsAsync.isLoading || capsAsync.hasError
              ? null
              : () => _handleCreate(context, ref),
          icon: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: const Text('生成链接'),
        ),
      ],
    );
  }

  Future<void> _handleCreate(BuildContext context, WidgetRef ref) async {
    setState(() {
      _creating = true;
      _resultUrl = null;
    });
    final item = ref.read(shareTargetItemProvider);
    final recipients = _scope == drive_models.LinkScope.users
        ? _recipientsController.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : null;
    try {
      final result = await ref.read(
        createShareLinkProvider(
          ShareLinkRequest(
            itemId: item.id,
            linkType: _linkType,
            scope: _scope,
            password: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
            retainInheritedPermissions: _retainInherited,
            recipients: recipients,
          ),
        ).future,
      );
      if (!mounted) return;
      setState(() {
        _resultUrl = result.webUrl ?? '';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分享链接已生成')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成失败：$err')));
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  void _copyAndNotify(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }
}

class _ScopeOption {
  const _ScopeOption({
    required this.label,
    required this.scope,
    required this.enabled,
    required this.icon,
  });

  final String label;
  final drive_models.LinkScope scope;
  final bool enabled;
  final IconData icon;
}

class _TypeOption {
  const _TypeOption({
    required this.label,
    required this.type,
    required this.icon,
    required this.enabled,
  });

  final String label;
  final drive_models.LinkType type;
  final IconData icon;
  final bool enabled;
}

class _ShareResult extends StatelessWidget {
  const _ShareResult({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分享链接',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            url.isEmpty ? '未返回链接，可能被策略阻止' : url,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: url.isEmpty ? null : onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('复制'),
            ),
          ),
        ],
      ),
    );
  }
}
