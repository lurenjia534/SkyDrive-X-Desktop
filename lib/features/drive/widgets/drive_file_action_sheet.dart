import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final sizeLabel = item.size != null
        ? formatFileSize(item.size!.toInt())
        : '未知大小';
    final typeLabel = item.mimeType ?? '未知类型';
    final modifiedLabel = item.lastModified ?? '未提供';
    final actionTextStyle = typography.sm.copyWith(
      fontWeight: FontWeight.w600,
      height: 1,
    );
    const actionPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final actionRadius = BorderRadius.circular(14);

    return SafeArea(
      child: SizedBox(
        height: double.infinity,
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(24),
              ),
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
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(24),
            ),
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
                        style: typography.lg.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.foreground,
                        ),
                      ),
                      const Spacer(),
                      FButton.icon(
                        onPress:
                            onClose ?? () => Navigator.of(context).maybePop(),
                        style: FButtonStyle.ghost(),
                        child: const Icon(FIcons.x, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _DetailsLoadBanner(itemId: item.id),
                  Text(
                    item.name,
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.foreground,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    buildDriveSubtitle(item),
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
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
                        child: FButton(
                          onPress: onClose ??
                              () => Navigator.of(context).maybePop(),
                          style: FButtonStyle.outline(
                            (style) => style.copyWith(
                              decoration: style.decoration.map(
                                (decoration) =>
                                    decoration.copyWith(borderRadius: actionRadius),
                              ),
                              contentStyle: (contentStyle) =>
                                  contentStyle.copyWith(
                                textStyle: FWidgetStateMap.all(
                                  actionTextStyle.copyWith(
                                    color: colors.foreground,
                                  ),
                                ),
                                iconStyle: FWidgetStateMap.all(
                                  IconThemeData(
                                    size: 16,
                                    color: colors.foreground,
                                  ),
                                ),
                                padding: actionPadding,
                                spacing: 8,
                              ),
                            ),
                          ),
                          prefix: const Icon(FIcons.arrowLeft, size: 16),
                          child: const Text('关闭'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FButton(
                          onPress: onDownload,
                          style: FButtonStyle.primary(
                            (style) => style.copyWith(
                              decoration: style.decoration.map(
                                (decoration) =>
                                    decoration.copyWith(borderRadius: actionRadius),
                              ),
                              contentStyle: (contentStyle) =>
                                  contentStyle.copyWith(
                                textStyle: FWidgetStateMap.all(
                                  actionTextStyle.copyWith(
                                    color: colors.primaryForeground,
                                  ),
                                ),
                                iconStyle: FWidgetStateMap.all(
                                  IconThemeData(
                                    size: 16,
                                    color: colors.primaryForeground,
                                  ),
                                ),
                                padding: actionPadding,
                                spacing: 8,
                              ),
                            ),
                          ),
                          prefix: const Icon(FIcons.download, size: 16),
                          child: const Text('下载到默认目录'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: FProgress(
          style: (style) => style.copyWith(
            constraints: const BoxConstraints.tightFor(height: 3),
            trackDecoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
            fillDecoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }
    if (state.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(FIcons.circleAlert, color: colors.error, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '属性加载失败',
                style: typography.sm.copyWith(color: colors.error),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FButton(
              onPress: () => ref.refresh(driveItemDetailsProvider(itemId)),
              style: FButtonStyle.ghost(),
              mainAxisSize: MainAxisSize.min,
              child: Text(
                '重试',
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

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

    final rows = <FItemMixin>[
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
      return Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FItemGroup(
        divider: FItemDivider.full,
        style: (style) => style.copyWith(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border.withValues(alpha: 0.6)),
          ),
          dividerColor: FWidgetStateMap.all(
            colors.border.withValues(alpha: 0.6),
          ),
          itemStyle: (itemStyle) => itemStyle.copyWith(
            margin: EdgeInsets.zero,
            decoration: FWidgetStateMap({
              WidgetState.hovered | WidgetState.pressed: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              WidgetState.any: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
              ),
            }),
            contentStyle: (contentStyle) => contentStyle.copyWith(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
              prefixIconStyle: FWidgetStateMap.all(
                IconThemeData(color: colors.foreground, size: 18),
              ),
              titleTextStyle: FWidgetStateMap.all(
                typography.sm.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitleTextStyle: FWidgetStateMap.all(
                typography.base.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        children: rows,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget with FItemMixin {
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
    final colors = context.theme.colors;
    return FItem(
      onPress: onTap,
      prefix: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.secondary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18),
      ),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
