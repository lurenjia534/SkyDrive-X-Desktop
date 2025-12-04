import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';

class DriveDownloadsPage extends ConsumerWidget {
  const DriveDownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(driveDownloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (queue.active.isEmpty &&
        queue.completed.isEmpty &&
        queue.failed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_download_rounded,
              size: 80,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无下载任务',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '在 Files 页面发起下载后，这里会显示任务进度与历史记录。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (queue.active.isNotEmpty)
          _DownloadSection(title: '下载中', tasks: queue.active, ref: ref),
        if (queue.failed.isNotEmpty)
          _DownloadSection(
            title: '失败',
            tasks: queue.failed,
            showError: true,
            ref: ref,
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
    this.showError = false,
    this.showPath = false,
    this.onClear,
  });

  final String title;
  final List<DownloadTask> tasks;
  final WidgetRef ref;
  final bool showError;
  final bool showPath;
  final AsyncCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (onClear != null)
              TextButton.icon(
                onPressed: () => unawaited(onClear!()),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清除失败'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...tasks.map(
          (task) => _DownloadTile(
            task: task,
            showError: showError,
            showPath: showPath,
            ref: ref,
          ),
        ),
        const SizedBox(height: 16),
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
  });

  final DownloadTask task;
  final bool showError;
  final bool showPath;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
      if (showError && task.errorMessage != null) {
        return Text('$statusLabel · ${task.errorMessage!}');
      }
      if (showPath && task.savedPath != null) {
        return Text('$statusLabel · ${task.savedPath!}');
      }
      if (task.status != DownloadStatus.inProgress) {
        final sizeInfo = task.sizeLabel != null ? '大小 $totalLabel' : '大小未知';
        return Text('$statusLabel · $sizeInfo');
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
          Text('$statusLabel · $details'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress?.clamp(0, 1), minHeight: 6),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          task.status == DownloadStatus.failed
              ? Icons.error_outline_rounded
              : Icons.download_done_rounded,
          color: task.status == DownloadStatus.failed
              ? colorScheme.error
              : colorScheme.primary,
        ),
        title: Text(task.item.name),
        subtitle: buildSubtitle(),
        trailing: task.status == DownloadStatus.inProgress
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Builder(
                    builder: (context) {
                      final cancelling =
                          ref.watch(driveDownloadManagerProvider.notifier).isCancelling(
                                task.item.id,
                              );
                      return IconButton(
                        icon: cancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.close_rounded),
                        tooltip: cancelling ? '取消中...' : '取消下载',
                        onPressed: cancelling
                            ? null
                            : () => unawaited(
                                  ref
                                      .read(driveDownloadManagerProvider.notifier)
                                      .cancelTask(task.item.id),
                                ),
                      );
                    },
                  ),
                ],
              )
            : IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '移除记录',
                onPressed: () => unawaited(
                  ref.read(driveDownloadManagerProvider.notifier).removeTask(
                        task.item.id,
                      ),
                ),
              ),
      ),
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
