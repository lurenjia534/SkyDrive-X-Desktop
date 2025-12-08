import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/drive_item_details_provider.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveFileActionSheet extends ConsumerWidget {
  const DriveFileActionSheet({
    super.key,
    required this.item,
    required this.onDownload,
    this.onClose,
  });

  final drive_api.DriveItemSummary item;
  final VoidCallback onDownload;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sizeLabel = item.size != null
        ? formatFileSize(item.size!.toInt())
        : '未知大小';
    final typeLabel = item.mimeType ?? '未知类型';
    final modifiedLabel = item.lastModified ?? '未提供';

    return SafeArea(
      child: SizedBox(
        height: double.infinity,
        child: Material(
          color: colorScheme.surface,
          elevation: 12,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '文件详情',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                      onPressed:
                          onClose ?? () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _DetailsLoadBanner(itemId: item.id),
                Text(
                  item.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  buildDriveSubtitle(item),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _DetailsSection(
                    baseSizeLabel: sizeLabel,
                    baseTypeLabel: typeLabel,
                    baseModifiedLabel: modifiedLabel,
                    item: item,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            onClose ?? () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('关闭'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('下载到默认目录'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _bigIntToSafeInt(BigInt value) {
  const maxSafeInt = 0x7fffffffffffffff;
  final max = BigInt.from(maxSafeInt);
  if (value > max) {
    return maxSafeInt;
  }
  return value.toInt();
}

class _DetailsLoadBanner extends ConsumerWidget {
  const _DetailsLoadBanner({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveItemDetailsProvider(itemId));
    final theme = Theme.of(context);
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: LinearProgressIndicator(
          minHeight: 3,
          backgroundColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
      );
    }
    if (state.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: theme.colorScheme.error, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '属性加载失败',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.refresh(driveItemDetailsProvider(itemId)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _DetailsSection extends ConsumerWidget {
  const _DetailsSection({
    required this.baseSizeLabel,
    required this.baseTypeLabel,
    required this.baseModifiedLabel,
    required this.item,
  });

  final String baseSizeLabel;
  final String baseTypeLabel;
  final String baseModifiedLabel;
  final drive_api.DriveItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(driveItemDetailsProvider(item.id));
    final details = detailsAsync.asData?.value;

    final sizeLabel = details?.size != null
        ? formatFileSize(_bigIntToSafeInt(details!.size!))
        : baseSizeLabel;
    final typeLabel = details?.mimeType ?? baseTypeLabel;
    final modifiedLabel = details?.lastModifiedAt ?? baseModifiedLabel;
    final createdLabel = details?.createdAt ?? '未知';
    final fsCreated = details?.fileSystemCreatedAt;
    final fsModified = details?.fileSystemModifiedAt;
    final webUrl = details?.webUrl ?? '未知';
    final downloadUrl = details?.downloadUrl != null ? '可用' : '暂无';
    final etag = details?.etag ?? '—';
    final ctag = details?.ctag ?? '—';
    final parentPath = details?.parentPath ?? '未知';
    final childCount = details?.childCount?.toInt();

    final rows = <Widget>[
      _InfoRow(
        icon: Icons.description_outlined,
        label: '文件类型',
        value: typeLabel,
      ),
      _InfoRow(
        icon: Icons.sd_storage_rounded,
        label: '大小',
        value: sizeLabel,
      ),
      _InfoRow(
        icon: Icons.schedule_rounded,
        label: '更新于',
        value: modifiedLabel,
      ),
      _InfoRow(
        icon: Icons.event_available_rounded,
        label: '创建于',
        value: createdLabel,
      ),
      if (fsCreated != null || fsModified != null)
        _InfoRow(
          icon: Icons.computer_rounded,
          label: '文件系统时间',
          value:
              '创建 ${fsCreated ?? "未知"} · 修改 ${fsModified ?? "未知"}',
        ),
      _InfoRow(
        icon: Icons.folder_open_rounded,
        label: '父路径',
        value: parentPath,
      ),
      if (childCount != null)
        _InfoRow(
          icon: Icons.insert_drive_file_rounded,
          label: '子项数量',
          value: '$childCount',
        ),
      _InfoRow(
        icon: Icons.language_rounded,
        label: 'Web 链接',
        value: webUrl,
      ),
      _InfoRow(
        icon: Icons.cloud_download_rounded,
        label: '下载链接',
        value: downloadUrl,
      ),
      _InfoRow(
        icon: Icons.tag_rounded,
        label: 'ETag',
        value: etag,
      ),
      _InfoRow(
        icon: Icons.bookmark_border_rounded,
        label: 'CTag',
        value: ctag,
      ),
    ];

    if (detailsAsync.isLoading && details == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: rows),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
