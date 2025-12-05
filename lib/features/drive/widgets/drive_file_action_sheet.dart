import 'package:flutter/material.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveFileActionSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
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
                      ],
                    ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
    );
  }
}
