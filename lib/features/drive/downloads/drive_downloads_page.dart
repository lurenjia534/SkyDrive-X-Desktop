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
          _DownloadSection(title: '下载中', tasks: queue.active),
        if (queue.failed.isNotEmpty)
          _DownloadSection(title: '失败', tasks: queue.failed, showError: true),
        if (queue.completed.isNotEmpty)
          _DownloadSection(
            title: '已完成',
            tasks: queue.completed,
            showPath: true,
          ),
      ],
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.title,
    required this.tasks,
    this.showError = false,
    this.showPath = false,
  });

  final String title;
  final List<DownloadTask> tasks;
  final bool showError;
  final bool showPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...tasks.map(
          (task) => _DownloadTile(
            task: task,
            showError: showError,
            showPath: showPath,
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
  });

  final DownloadTask task;
  final bool showError;
  final bool showPath;

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

    final subtitle = showError && task.errorMessage != null
        ? task.errorMessage!
        : showPath && task.savedPath != null
        ? task.savedPath!
        : task.sizeLabel != null
        ? '大小 ${formatFileSize(_bigIntToSafeInt(task.sizeLabel))}'
        : '大小未知';

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
        subtitle: Text('$statusLabel · $subtitle'),
        trailing: task.status == DownloadStatus.inProgress
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
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
