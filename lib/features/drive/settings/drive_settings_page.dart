import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_concurrency_provider.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/utils/download_destination.dart';

class DriveSettingsPage extends StatelessWidget {
  const DriveSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: const [
        _SettingsSectionTitle(label: 'OneDrive 信息'),
        SizedBox(height: 8),
        _DriveInfoTile(),
        SizedBox(height: 24),
        _SettingsSectionTitle(label: '外观'),
        SizedBox(height: 8),
        _FakeToggleTile(label: '跟随系统主题', description: '自动在浅色和深色主题间切换。'),
        SizedBox(height: 24),
        _SettingsSectionTitle(label: '同步'),
        SizedBox(height: 8),
        _SettingsSyncTile(),
        SizedBox(height: 24),
        _SettingsSectionTitle(label: '下载'),
        SizedBox(height: 8),
        _DownloadDirectoryTile(),
        SizedBox(height: 16),
        _DownloadConcurrencyTile(),
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FakeToggleTile extends StatelessWidget {
  const _FakeToggleTile({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const FSwitch(value: true, enabled: false),
        ],
      ),
    );
  }
}

class _SettingsSyncTile extends StatelessWidget {
  const _SettingsSyncTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '同步状态',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('立即同步'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '上次同步：刚刚 · 计划间隔：15 分钟',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    if (state.isLoading) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.hasError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('无法获取 OneDrive 信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(driveInfoProvider.notifier).refreshInfo(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
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

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '存储配额',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '账户类型：$accountType',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    ref.read(driveInfoProvider.notifier).refreshInfo(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.person_rounded, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (ownerUpn != null)
                      Text(
                        ownerUpn,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _QuotaMetric(label: '总空间', value: totalLabel),
                _QuotaMetric(label: '已用', value: usedLabel),
                _QuotaMetric(label: '剩余', value: remainingLabel),
                _QuotaMetric(label: '回收站', value: deletedLabel),
              ];
              final isWide = constraints.maxWidth >= 520;
              if (isWide) {
                return Row(
                  children: metrics
                      .map((metric) => Expanded(child: metric))
                      .toList(growable: false),
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: metrics[0]),
                      const SizedBox(width: 12),
                      Expanded(child: metrics[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: metrics[2]),
                      const SizedBox(width: 12),
                      Expanded(child: metrics[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.shield_moon_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '状态：$quotaState',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: content,
    );
  }
}

class _QuotaMetric extends StatelessWidget {
  const _QuotaMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    if (state.isLoading) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.hasError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('无法获取下载路径', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
          ),
        ],
      );
    } else {
      final path = state.value ?? '';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '下载保存目录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref
                    .read(downloadDirectoryProvider.notifier)
                    .refreshDirectory(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            path,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _promptForPath(context, ref, path),
                icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                label: const Text('修改路径'),
              ),
              TextButton.icon(
                onPressed: () => _restoreDefault(context, ref),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('恢复默认'),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: content,
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
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    if (state.isLoading) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.hasError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('无法获取并行下载数量', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
          ),
        ],
      );
    } else {
      final value = state.value ?? _options.first;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '同时下载的任务数量',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref
                    .read(downloadConcurrencyProvider.notifier)
                    .refreshLimit(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '限制后台并行下载任务数，避免占满网络带宽。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: content,
    );
  }
}
