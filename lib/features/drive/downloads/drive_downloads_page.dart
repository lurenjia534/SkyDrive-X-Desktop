import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';

class DriveDownloadsPage extends ConsumerWidget {
  const DriveDownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(driveDownloadManagerProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    if (queue.active.isEmpty &&
        queue.completed.isEmpty &&
        queue.failed.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: FCard.raw(
            style: (style) => style.copyWith(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.barrier.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.cloud_download_rounded,
                      size: 34,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '暂无下载任务',
                    style: typography.lg.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在 Files 页面发起下载后，这里会显示任务进度与历史记录。',
                    textAlign: TextAlign.center,
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        if (queue.active.isNotEmpty)
          _DownloadSection(
            title: '下载中',
            tasks: queue.active,
            ref: ref,
            colors: colors,
            typography: typography,
          ),
        if (queue.failed.isNotEmpty)
          _DownloadSection(
            title: '失败',
            tasks: queue.failed,
            showError: true,
            ref: ref,
            colors: colors,
            typography: typography,
            onClear: ref
                .read(driveDownloadManagerProvider.notifier)
                .clearFailedTasks,
          ),
        if (queue.completed.isNotEmpty)
          _DownloadSection(
            title: '已完成',
            tasks: queue.completed,
            showPath: true,
            ref: ref,
            colors: colors,
            typography: typography,
          ),
      ],
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.title,
    required this.tasks,
    required this.ref,
    required this.colors,
    required this.typography,
    this.showError = false,
    this.showPath = false,
    this.onClear,
  });

  final String title;
  final List<DownloadTask> tasks;
  final WidgetRef ref;
  final FColors colors;
  final FTypography typography;
  final bool showError;
  final bool showPath;
  final AsyncCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final headerStyle = typography.base.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.foreground,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(title, style: headerStyle),
                  const SizedBox(width: 8),
                  _SectionCount(
                    count: tasks.length,
                    colors: colors,
                    typography: typography,
                  ),
                ],
              ),
            ),
            if (onClear != null)
              FButton(
                onPress: () => unawaited(onClear!()),
                style: FButtonStyle.ghost(),
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(Icons.delete_sweep_rounded, size: 16),
                child: Text(
                  '清除失败',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FCard.raw(
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
          child: Column(
            children: [
              for (var i = 0; i < tasks.length; i++) ...[
                _DownloadTile(
                  task: tasks[i],
                  showError: showError,
                  showPath: showPath,
                  ref: ref,
                  colors: colors,
                  typography: typography,
                ),
                if (i != tasks.length - 1)
                  Divider(
                    height: 1,
                    color: colors.border.withValues(alpha: 0.6),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.task,
    required this.showError,
    required this.showPath,
    required this.ref,
    required this.colors,
    required this.typography,
  });

  final DownloadTask task;
  final bool showError;
  final bool showPath;
  final WidgetRef ref;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final statusLabel = () {
      switch (task.status) {
        case DownloadStatus.inProgress:
          return '下载中';
        case DownloadStatus.completed:
          return '已完成';
        case DownloadStatus.failed:
          return '失败';
      }
    }();

    final manager = ref.read(driveDownloadManagerProvider.notifier);
    final progress = task.progressRatio;
    final downloadedLabel = task.bytesDownloaded != null
        ? formatFileSize(_bigIntToSafeInt(task.bytesDownloaded))
        : '0 B';
    final totalLabel = task.sizeLabel != null
        ? formatFileSize(_bigIntToSafeInt(task.sizeLabel))
        : '未知';
    final speed = manager.speedFor(task.item.id);
    final speedLabel = _formatSpeed(speed);

    Widget buildSubtitle() {
      final subtitleStyle = typography.sm.copyWith(
        color: colors.mutedForeground,
        height: 1.4,
      );
      if (showError && task.errorMessage != null) {
        return Text(
          '$statusLabel · ${task.errorMessage!}',
          style: subtitleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      }
      if (showPath && task.savedPath != null) {
        return Text(
          '$statusLabel · ${task.savedPath!}',
          style: subtitleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      if (task.status != DownloadStatus.inProgress) {
        final sizeInfo = task.sizeLabel != null ? '大小 $totalLabel' : '大小未知';
        return Text('$statusLabel · $sizeInfo', style: subtitleStyle);
      }
      final details = [
        if (progress != null)
          '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
        '$downloadedLabel / $totalLabel',
        if (speedLabel != null) speedLabel,
      ].where((element) => element.isNotEmpty).join(' · ');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$statusLabel · $details', style: subtitleStyle),
          const SizedBox(height: 8),
          if (progress != null)
            FDeterminateProgress(
              value: progress.clamp(0, 1),
              style: (style) => style.copyWith(
                constraints: const BoxConstraints.tightFor(height: 8),
                trackDecoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                fillDecoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            )
          else
            FProgress(
              style: (style) => style.copyWith(
                constraints: const BoxConstraints.tightFor(height: 8),
                trackDecoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                fillDecoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      );
    }

    final isFailed = task.status == DownloadStatus.failed;
    final isInProgress = task.status == DownloadStatus.inProgress;
    final leadingColor = isFailed ? colors.error : colors.primary;
    final leadingIcon = isFailed
        ? Icons.error_outline_rounded
        : (isInProgress
            ? Icons.cloud_download_rounded
            : Icons.download_done_rounded);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: leadingColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(leadingIcon, color: leadingColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.item.name,
                  style: typography.base.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                buildSubtitle(),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Align(
            alignment: Alignment.topRight,
            child: _DownloadAction(
              task: task,
              ref: ref,
              colors: colors,
              isInProgress: isInProgress,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCount extends StatelessWidget {
  const _SectionCount({
    required this.count,
    required this.colors,
    required this.typography,
  });

  final int count;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Text(
        count.toString(),
        style: typography.xs.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DownloadAction extends StatelessWidget {
  const _DownloadAction({
    required this.task,
    required this.ref,
    required this.colors,
    required this.isInProgress,
  });

  final DownloadTask task;
  final WidgetRef ref;
  final FColors colors;
  final bool isInProgress;

  @override
  Widget build(BuildContext context) {
    if (isInProgress) {
      final cancelling =
          ref.watch(driveDownloadManagerProvider.notifier).isCancelling(
                task.item.id,
              );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: FCircularProgress.loader(
              style: (style) => style.copyWith(
                iconStyle: IconThemeData(
                  color: colors.primary,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FButton.icon(
            onPress: cancelling
                ? null
                : () => unawaited(
                      ref
                          .read(driveDownloadManagerProvider.notifier)
                          .cancelTask(task.item.id),
                    ),
            style: FButtonStyle.outline(),
            child: Icon(
              cancelling ? Icons.hourglass_top_rounded : Icons.close_rounded,
              size: 16,
            ),
          ),
        ],
      );
    }
    return FButton.icon(
      onPress: () => unawaited(
        ref.read(driveDownloadManagerProvider.notifier).removeTask(task.item.id),
      ),
      style: FButtonStyle.outline(),
      child: const Icon(Icons.delete_outline_rounded, size: 16),
    );
  }
}

int _bigIntToSafeInt(BigInt? value) {
  if (value == null) return 0;
  const maxSafeInt = 0x7fffffffffffffff;
  final max = BigInt.from(maxSafeInt);
  if (value > max) {
    return maxSafeInt;
  }
  return value.toInt();
}

/// 将 bytes/s 转换为简洁的人类可读文案。
String? _formatSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond.isNaN || bytesPerSecond <= 0) {
    return null;
  }
  const kb = 1024;
  const mb = kb * 1024;
  if (bytesPerSecond >= mb) {
    return '${(bytesPerSecond / mb).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= kb) {
    return '${(bytesPerSecond / kb).toStringAsFixed(1)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}
