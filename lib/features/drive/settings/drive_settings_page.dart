import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_concurrency_provider.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/utils/download_destination.dart';

class DriveSettingsPage extends ConsumerStatefulWidget {
  const DriveSettingsPage({super.key});

  @override
  ConsumerState<DriveSettingsPage> createState() =>
      _DriveSettingsPageState();
}

class _DriveSettingsPageState extends ConsumerState<DriveSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const _DriveInfoTile(),
                const SizedBox(height: 24),
                const _FakeToggleTile(
                  label: '跟随系统主题',
                  description: '自动在浅色和深色主题间切换。',
                ),
                const SizedBox(height: 24),
                const _SettingsSyncTile(),
                const SizedBox(height: 24),
                const Column(
                  children: [
                    _DownloadDirectoryTile(),
                    SizedBox(height: 16),
                    _DownloadConcurrencyTile(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard.raw(
      style: (style) => style.copyWith(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: colors.barrier.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: child,
      ),
    );
  }
}

class _SettingsCardHeader extends StatelessWidget {
  const _SettingsCardHeader({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _FakeToggleTile extends StatelessWidget {
  const _FakeToggleTile({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return _SettingsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '外观',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: typography.xl.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const FSwitch(value: true, enabled: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSyncTile extends StatelessWidget {
  const _SettingsSyncTile();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return _SettingsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '同步',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '同步状态',
                          style: typography.xl.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF34D399), // Green dot
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6), // Light grey pill
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '上次同步 : 刚刚 · 计划间隔 : 15 分钟',
                        style: typography.sm.copyWith(
                          color: const Color(0xFF6B7280), // Muted text
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FButton(
                onPress: () {},
                style: FButtonStyle.primary(
                  (style) => style.copyWith(
                    decoration: FWidgetStateMap.all(
                      BoxDecoration(
                        color: colors.foreground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    contentStyle: (contentStyle) => contentStyle.copyWith(
                      textStyle: FWidgetStateMap.all(
                        typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.background,
                          height: 1,
                        ),
                      ),
                      iconStyle: FWidgetStateMap.all(
                        IconThemeData(
                          size: 16,
                          color: colors.background,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      spacing: 8,
                    ),
                  ),
                ),
                prefix: const Icon(FIcons.rotateCw),
                child: const Text('立即同步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriveInfoTile extends ConsumerWidget {
  const _DriveInfoTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveInfoProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(driveInfoProvider.notifier).refreshInfo(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.rotateCw, size: 16),
    );

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '无法获取 OneDrive 信息',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () => ref.read(driveInfoProvider.notifier).refreshInfo(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.rotateCcw, size: 16),
            child: Text(
              '重试',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final info = state.value!;
      final owner = info.owner;
      final ownerName =
          owner?.displayName ?? owner?.userPrincipalName ?? '未提供';
      final ownerUpn = owner?.userPrincipalName;
      final accountType = info.driveType ?? '未知';
      final quota = info.quota;
      final quotaState = quota?.state ?? '未知';
      final totalLabel = _formatSize(quota?.total);
      final usedLabel = _formatSize(quota?.used);
      final remainingLabel = _formatSize(quota?.remaining);
      final deletedLabel = _formatSize(quota?.deleted);
      final usedRatio = (quota?.used != null && quota?.total != null)
          ? (quota!.used!.toDouble() / quota.total!.toDouble())
          : null;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OneDrive 信息',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '存储配额',
                      style: typography.xl2.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '账户类型 : $accountType',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              refreshAction,
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.secondary.withValues(alpha: 0.5),
                ),
                child: Center(
                  child: Icon(
                    FIcons.user,
                    color: colors.foreground.withValues(alpha: 0.7),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: typography.lg.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (ownerUpn != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Authenticated User',
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _QuotaMetricCard(
                  label: '总空间',
                  value: totalLabel,
                  statusLabel: quotaState,
                ),
                _QuotaMetricCard(
                  label: '已用',
                  value: usedLabel,
                  progress: usedRatio,
                ),
                _QuotaMetricCard(label: '剩余', value: remainingLabel),
                _QuotaMetricCard(label: '回收站', value: deletedLabel),
              ];
              const gap = 16.0;
              final width = constraints.maxWidth;
              final columns = width >= 740
                  ? 4
                  : width >= 420
                      ? 2
                      : 1;
              final cardWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map((metric) => SizedBox(width: cardWidth, child: metric))
                    .toList(growable: false),
              );
            },
          ),
        ],
      );
    }

    return _SettingsCard(
      padding: const EdgeInsets.all(24),
      child: body,
    );
  }
}

class _QuotaMetricCard extends StatelessWidget {
  const _QuotaMetricCard({
    required this.label,
    required this.value,
    this.progress,
    this.statusLabel,
  });

  final String label;
  final String value;
  final double? progress;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final hasProgress = progress != null;
    final chipBg = const Color(0xFFDCFCE7);
    final chipFg = const Color(0xFF16A34A);

    return Container(
      height: 140, // Fixed height for uniformity
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB), // Very light grey/white
        borderRadius: BorderRadius.circular(24),
        // border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: typography.xl2.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827), // Dark text
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: typography.sm.copyWith(
                  color: const Color(0xFF6B7280), // Muted text
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (statusLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FIcons.circleCheck, size: 14, color: chipFg),
                  const SizedBox(width: 6),
                  Text(
                    '状态 : $statusLabel',
                    style: typography.xs.copyWith(
                      color: chipFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else if (hasProgress)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FDeterminateProgress(
                  value: progress!.clamp(0, 1),
                  style: (style) => style.copyWith(
                    constraints: const BoxConstraints.tightFor(height: 8),
                    trackDecoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    fillDecoration: BoxDecoration(
                      color: const Color(0xFF3B82F6), // Blue progress
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            )
          else
            const SizedBox(), // Spacer if nothing else
        ],
      ),
    );
  }
}

String _formatSize(BigInt? value) {
  if (value == null) return '未知';
  return formatFileSize(_bigIntToSafeInt(value));
}

int _bigIntToSafeInt(BigInt value) {
  const maxSafeInt = 0x7fffffffffffffff;
  final max = BigInt.from(maxSafeInt);
  if (value > max) {
    return maxSafeInt;
  }
  return value.toInt();
}

class _DownloadDirectoryTile extends ConsumerWidget {
  const _DownloadDirectoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadDirectoryProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
    );

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '无法获取下载路径',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () =>
                ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              '重试',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final path = state.value ?? '';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下载保存目录',
            style: typography.base.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            path,
            style: typography.base.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FButton(
                onPress: () => _promptForPath(context, ref, path),
                style: FButtonStyle.outline(),
                prefix: const Icon(FIcons.mapPin, size: 16),
                child: Text(
                  '修改路径',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              FButton(
                onPress: () => _restoreDefault(context, ref),
                style: FButtonStyle.ghost(),
                prefix: const Icon(FIcons.undo, size: 16),
                child: Text(
                  '恢复默认',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCardHeader(label: '下载位置', action: refreshAction),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Future<void> _promptForPath(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改下载目录'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '目录路径'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(result);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载路径已更新')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：$err')));
      }
    }
  }

  Future<void> _restoreDefault(BuildContext context, WidgetRef ref) async {
    final defaultPath = defaultDownloadDirectory();
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(defaultPath);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复默认下载路径')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$err')));
      }
    }
  }
}

class _DownloadConcurrencyTile extends ConsumerWidget {
  const _DownloadConcurrencyTile();

  static const _options = [1, 2, 3, 4, 5, 6, 7, 8];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadConcurrencyProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
    );

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '无法获取并行下载数量',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () =>
                ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              '重试',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final value = state.value ?? _options.first;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '同时下载的任务数量',
            style: typography.base.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '限制后台并行下载任务数，避免占满网络带宽。',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FSelect<int>(
                  items: {
                    for (final option in _options) '$option 个任务': option,
                  },
                  initialValue: value,
                  hint: '选择任务数量',
                  onChange: (selected) {
                    if (selected != null && selected != value) {
                      unawaited(
                        ref
                            .read(downloadConcurrencyProvider.notifier)
                            .updateLimit(selected),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '当前：$value 个',
                style: typography.sm.copyWith(color: colors.foreground),
              ),
            ],
          ),
        ],
      );
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCardHeader(label: '下载并发', action: refreshAction),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
