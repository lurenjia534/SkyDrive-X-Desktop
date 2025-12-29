import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_share_provider.dart';
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

class DriveShareDialog extends ConsumerStatefulWidget {
  const DriveShareDialog({super.key, required this.animation});

  final Animation<double> animation;

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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    Widget content;
    if (capsAsync.isLoading) {
      content = _LoadingState(typography: typography, colors: colors);
    } else if (capsAsync.hasError) {
      content = _ErrorState(
        error: capsAsync.error,
        onRetry: () => ref.refresh(shareCapabilitiesProvider),
      );
    } else {
      final caps = capsAsync.value!;
      final canEmbed = caps.canEmbedLink;
      final canOrg = caps.canOrgScopeLink;
      final canPassword = caps.canPassword;
      final scopeOptions = <_ShareOption<drive_models.LinkScope>>[
        _ShareOption(
          label: '任何知道链接的人',
          value: drive_models.LinkScope.anonymous,
          enabled: true,
          icon: Icons.public_rounded,
        ),
        _ShareOption(
          label: '仅组织内人员',
          value: drive_models.LinkScope.organization,
          enabled: canOrg,
          icon: Icons.apartment_rounded,
        ),
        _ShareOption(
          label: '指定人员',
          value: drive_models.LinkScope.users,
          enabled: true,
          icon: Icons.people_alt_rounded,
        ),
      ];
      final typeOptions = <_ShareOption<drive_models.LinkType>>[
        _ShareOption(
          label: '仅查看',
          value: drive_models.LinkType.view,
          icon: Icons.visibility_rounded,
          enabled: true,
        ),
        _ShareOption(
          label: '可编辑',
          value: drive_models.LinkType.edit,
          icon: Icons.edit_rounded,
          enabled: true,
        ),
        _ShareOption(
          label: '嵌入',
          value: drive_models.LinkType.embed,
          icon: Icons.code_rounded,
          enabled: canEmbed,
        ),
      ];

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '分享 “${item.name}”',
            style: typography.base.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _OptionGroup<drive_models.LinkType>(
            title: '链接类型',
            options: typeOptions,
            selected: _linkType,
            onSelect: (value) => setState(() => _linkType = value),
          ),
          const SizedBox(height: 16),
          _OptionGroup<drive_models.LinkScope>(
            title: '访问范围',
            options: scopeOptions,
            selected: _scope,
            onSelect: (value) => setState(() => _scope = value),
          ),
          const SizedBox(height: 12),
          FCheckbox(
            value: _retainInherited,
            onChange: (value) =>
                setState(() => _retainInherited = value),
            label: const Text('保留继承的权限（避免覆盖父级设置）'),
          ),
          if (canPassword) ...[
            const SizedBox(height: 12),
            FTextField(
              controller: _passwordController,
              label: const Text('密码（可选，仅个人版）'),
              obscureText: true,
              prefixBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.only(left: 14, right: 10),
                child: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ),
          ],
          if (_scope == drive_models.LinkScope.users) ...[
            const SizedBox(height: 12),
            FTextField(
              controller: _recipientsController,
              label: const Text('指定人员邮箱（逗号分隔）'),
              prefixBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.only(left: 14, right: 10),
                child: Icon(Icons.mail_outline_rounded, size: 18),
              ),
            ),
          ],
          if (_resultUrl != null) ...[
            const SizedBox(height: 16),
            _ShareResult(
              url: _resultUrl!,
              onCopy: () => _copyAndNotify(context, _resultUrl!),
            ),
          ],
        ],
      );
    }

    return FDialog(
      animation: widget.animation,
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 640),
      title: Row(
        children: [
          const Icon(Icons.share_outlined, size: 20),
          const SizedBox(width: 8),
          Text(
            '创建分享链接',
            style: typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
        ],
      ),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(child: content),
      ),
      direction: Axis.horizontal,
      actions: [
        FButton(
          onPress: _creating ? null : () => Navigator.of(context).pop(),
          style: FButtonStyle.outline(),
          child: const Text('取消'),
        ),
        FButton(
          onPress: _creating || capsAsync.isLoading || capsAsync.hasError
              ? null
              : () => _handleCreate(context, ref),
          style: FButtonStyle.primary(),
          prefix: _creating
              ? FCircularProgress.loader(
                  style: (style) => style.copyWith(
                    iconStyle: IconThemeData(
                      color: colors.primaryForeground,
                      size: 16,
                    ),
                  ),
                )
              : const Icon(Icons.link_rounded, size: 16),
          child: const Text('生成链接'),
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
      _showToast(context, '分享链接已生成');
    } catch (err) {
      if (!mounted) return;
      _showToast(context, '生成失败：$err');
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
    _showToast(context, '已复制到剪贴板');
  }

  void _showToast(BuildContext context, String message) {
    if (context.findAncestorStateOfType<FToasterState>() != null) {
      showFToast(context: context, title: Text(message));
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ShareOption<T> {
  const _ShareOption({
    required this.label,
    required this.value,
    required this.enabled,
    required this.icon,
  });

  final String label;
  final T value;
  final bool enabled;
  final IconData icon;
}

class _OptionGroup<T> extends StatelessWidget {
  const _OptionGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final List<_ShareOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: typography.sm.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        FTileGroup(
          divider: FItemDivider.indented,
          children: options
              .map(
                (option) => FTile(
                  enabled: option.enabled,
                  selected: option.value == selected,
                  onPress:
                      option.enabled ? () => onSelect(option.value) : null,
                  prefix: Icon(
                    option.icon,
                    size: 18,
                    color: option.enabled
                        ? colors.foreground
                        : colors.mutedForeground,
                  ),
                  title: Text(
                    option.label,
                    style: typography.base.copyWith(
                      color: option.enabled
                          ? colors.foreground
                          : colors.mutedForeground,
                    ),
                  ),
                  suffix: Icon(
                    FIcons.check,
                    size: 16,
                    color: option.value == selected
                        ? colors.primary
                        : Colors.transparent,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ShareResult extends StatelessWidget {
  const _ShareResult({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    return FCard.raw(
      style: (style) => style.copyWith(
        decoration: BoxDecoration(
          color: colors.secondary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分享链接',
              style: typography.sm.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              url.isEmpty ? '未返回链接，可能被策略阻止' : url,
              style: typography.base.copyWith(fontWeight: FontWeight.w600),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                onPress: url.isEmpty ? null : onCopy,
                style: FButtonStyle.ghost(),
                prefix: const Icon(Icons.copy_rounded, size: 16),
                child: const Text('复制'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.typography, required this.colors});

  final FTypography typography;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FCircularProgress.loader(
              style: (style) => style.copyWith(
                iconStyle: IconThemeData(color: colors.primary, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '正在加载分享能力…',
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final typography = theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FAlert(
          style: FAlertStyle.destructive(),
          title: const Text('无法获取分享能力'),
          subtitle: Text(error?.toString() ?? '未知错误'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FButton(
            onPress: onRetry,
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              '重试',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
