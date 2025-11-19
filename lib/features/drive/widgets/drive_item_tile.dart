import 'package:flutter/material.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveItemTile extends StatelessWidget {
  const DriveItemTile({
    super.key,
    required this.item,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
    this.trailing,
  });

  final drive_api.DriveItemSummary item;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isFolder = item.isFolder;
    final hasThumbnail = _shouldShowThumbnail(item);
    final thumbnailUrl = item.thumbnailUrl;
    final iconData = isFolder
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;
    final iconBackground = isFolder
        ? colorScheme.primaryContainer.withOpacity(0.6)
        : colorScheme.surfaceVariant.withOpacity(0.6);
    final iconColor = isFolder
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        hoverColor: colorScheme.primary.withOpacity(0.05),
        splashColor: colorScheme.primary.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _ThumbnailImage(
                          url: thumbnailUrl!,
                          itemId: item.id,
                          fallback: _DriveTileIcon(
                            icon: iconData,
                            background: iconBackground,
                            iconColor: iconColor,
                          ),
                        ),
                      )
                    : _DriveTileIcon(
                        icon: iconData,
                        background: iconBackground,
                        iconColor: iconColor,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveTileIcon extends StatelessWidget {
  const _DriveTileIcon({
    required this.icon,
    required this.background,
    required this.iconColor,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor),
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({
    required this.url,
    required this.itemId,
    required this.fallback,
  });

  final String url;
  final String itemId;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return fallback;
      },
    );
  }
}

///决定是否应该为此驱动器项目呈现远程缩略图。
///一些图表条目（文件夹、0字节文件、没有`thumbnailUrl`的项目）
///没有有效的缩略图，如果我们尝试，将会触发 416 响应。
bool _shouldShowThumbnail(drive_api.DriveItemSummary item) {
  if (item.isFolder) return false;
  final url = item.thumbnailUrl;
  if (url == null || url.isEmpty) return false;
  final size = item.size;
  if (size != null && size == BigInt.zero) {
    // 0B 文件在 Graph 端不会返回有效缩略图，直接回退为图标
    return false;
  }
  return true;
}
