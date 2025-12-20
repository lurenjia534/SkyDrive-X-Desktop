import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';

/// 上传管理器页面：展示进行中、失败、已完成任务。
class DriveUploadsPage extends ConsumerWidget {
  const DriveUploadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(driveUploadManagerProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    // 空状态：没有任何上传记录时的提示。
    if (queue.active.isEmpty && queue.completed.isEmpty && queue.failed.isEmpty) {
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
                      FIcons.cloudUpload,
                      size: 34,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '暂无上传任务',
                    style: typography.lg.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在侧边栏点击上传入口后，这里会显示正在上传和历史记录。',
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
          _UploadSection(
            title: '上传中',
            tasks: queue.active,
            ref: ref,
            colors: colors,
            typography: typography,
          ),
        if (queue.failed.isNotEmpty)
          _UploadSection(
            title: '失败',
            tasks: queue.failed,
            ref: ref,
            showError: true,
            colors: colors,
            typography: typography,
            onClear: ref.read(driveUploadManagerProvider.notifier).clearFailedTasks,
          ),
        if (queue.completed.isNotEmpty)
          _UploadSection(
            title: '已完成',
            tasks: queue.completed,
            ref: ref,
            colors: colors,
            typography: typography,
          ),
      ],
    );
  }
}

class _UploadSection extends StatelessWidget {
  const _UploadSection({
    required this.title,
    required this.tasks,
    required this.ref,
    required this.colors,
    required this.typography,
    this.showError = false,
    this.onClear,
  });

  final String title;
  final List<UploadTask> tasks;
  final WidgetRef ref;
  final FColors colors;
  final FTypography typography;
  final bool showError;
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
                prefix: const Icon(FIcons.trash2, size: 16),
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
                _UploadTile(
                  task: tasks[i],
                  showError: showError,
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

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.task,
    required this.showError,
    required this.ref,
    required this.colors,
    required this.typography,
  });

  final UploadTask task;
  final bool showError;
  final WidgetRef ref;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final manager = ref.read(driveUploadManagerProvider.notifier);
    final progress = task.progressRatio;
    // 进度/速度显示的格式化值，UI 仅做展示。
    final uploadedLabel = task.bytesUploaded != null
        ? _formatFileSize(task.bytesUploaded!)
        : '0 B';
    final totalLabel = task.size != null ? _formatFileSize(task.size!) : '未知';
    final speed = manager.speedFor(task.taskId);
    final speedLabel = _formatSpeed(speed);

    final statusLabel = () {
      switch (task.status) {
        case UploadStatus.inProgress:
          return '上传中';
        case UploadStatus.completed:
          return '已完成';
        case UploadStatus.failed:
          return '失败';
        case UploadStatus.cancelled:
          return '已取消';
      }
    }();

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
      if (task.status != UploadStatus.inProgress) {
        final sizeInfo = task.size != null ? '大小 $totalLabel' : '大小未知';
        return Text('$statusLabel · $sizeInfo', style: subtitleStyle);
      }
      final details = [
        if (progress != null)
          '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
        '$uploadedLabel / $totalLabel',
        if (speedLabel != null) speedLabel,
      ].where((e) => e.isNotEmpty).join(' · ');
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

    final isFailed =
        task.status == UploadStatus.failed ||
        task.status == UploadStatus.cancelled;
    final isInProgress = task.status == UploadStatus.inProgress;
    final leadingColor = isFailed ? colors.error : colors.primary;
    final leadingIcon = isFailed
        ? FIcons.circleAlert
        : (isInProgress ? FIcons.cloudUpload : FIcons.upload);

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
                  task.fileName,
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
            child: _UploadAction(
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

class _UploadAction extends StatelessWidget {
  const _UploadAction({
    required this.task,
    required this.ref,
    required this.colors,
    required this.isInProgress,
  });

  final UploadTask task;
  final WidgetRef ref;
  final FColors colors;
  final bool isInProgress;

  @override
  Widget build(BuildContext context) {
    final manager = ref.read(driveUploadManagerProvider.notifier);
    if (isInProgress) {
      final cancelling =
          ref.watch(driveUploadManagerProvider.notifier).isCancelling(
                task.taskId,
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
            onPress: cancelling ? null : () => manager.cancelTask(task.taskId),
            style: FButtonStyle.outline(),
            child: Icon(
              cancelling ? FIcons.hourglass : FIcons.x,
              size: 16,
            ),
          ),
        ],
      );
    }
    return FButton.icon(
      onPress: () => manager.removeTask(task.taskId),
      style: FButtonStyle.outline(),
      child: const Icon(FIcons.trash2, size: 16),
    );
  }
}

String _formatFileSize(BigInt bytes) {
  final bytesInt = bytes.toDouble();
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytesInt >= gb) {
    return '${(bytesInt / gb).toStringAsFixed(2)} GB';
  }
  if (bytesInt >= mb) {
    return '${(bytesInt / mb).toStringAsFixed(1)} MB';
  }
  if (bytesInt >= kb) {
    return '${(bytesInt / kb).toStringAsFixed(1)} KB';
  }
  return '${bytesInt.toStringAsFixed(0)} B';
}

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
