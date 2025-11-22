import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';

/// 上传管理器页面：展示进行中、失败、已完成任务。
class DriveUploadsPage extends ConsumerWidget {
  const DriveUploadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(driveUploadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 空状态：没有任何上传记录时的提示。
    if (queue.active.isEmpty && queue.completed.isEmpty && queue.failed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_upload_rounded,
              size: 80,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无上传任务',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '在侧边栏点击上传入口后，这里会显示正在上传和历史记录。',
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
          _UploadSection(title: '上传中', tasks: queue.active, ref: ref),
        if (queue.failed.isNotEmpty)
          _UploadSection(
            title: '失败',
            tasks: queue.failed,
            ref: ref,
            showError: true,
            onClear: ref.read(driveUploadManagerProvider.notifier).clearFailedTasks,
          ),
        if (queue.completed.isNotEmpty)
          _UploadSection(
            title: '已完成',
            tasks: queue.completed,
            ref: ref,
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
    this.showError = false,
    this.onClear,
  });

  final String title;
  final List<UploadTask> tasks;
  final WidgetRef ref;
  final bool showError;
  final AsyncCallback? onClear;

  @override
  Widget build(BuildContext context) {
    // 单个分组（上传中/失败/已完成）的列表。
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
                onPressed: () => onClear!(),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清除失败'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...tasks.map(
          (task) => _UploadTile(
            task: task,
            showError: showError,
            ref: ref,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.task,
    required this.showError,
    required this.ref,
  });

  final UploadTask task;
  final bool showError;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
      if (showError && task.errorMessage != null) {
        return Text('$statusLabel · ${task.errorMessage!}');
      }
      if (task.status != UploadStatus.inProgress) {
        final sizeInfo = task.size != null ? '大小 $totalLabel' : '大小未知';
        return Text('$statusLabel · $sizeInfo');
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
          Text('$statusLabel · $details'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress?.clamp(0, 1), minHeight: 6),
        ],
      );
    }

    final isCancelling =
        ref.watch(driveUploadManagerProvider.notifier).isCancelling(task.taskId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          task.status == UploadStatus.failed || task.status == UploadStatus.cancelled
              ? Icons.error_outline_rounded
              : Icons.cloud_upload_rounded,
          color: task.status == UploadStatus.failed || task.status == UploadStatus.cancelled
              ? colorScheme.error
              : colorScheme.primary,
        ),
        title: Text(task.fileName),
        subtitle: buildSubtitle(),
        trailing: task.status == UploadStatus.inProgress
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  IconButton(
                    icon: isCancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close_rounded),
                    tooltip: isCancelling ? '取消中...' : '取消上传',
                    onPressed: isCancelling
                        ? null
                        : () => manager.cancelTask(task.taskId),
                  ),
                ],
              )
            : IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '移除记录',
                onPressed: () => manager.removeTask(task.taskId),
              ),
      ),
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
