import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveItemTile extends StatelessWidget {
  const DriveItemTile({
    super.key,
    required this.item,
    required this.subtitle,
    required this.onTap,
    this.onSecondaryTapDown,
    this.trailing,
  });

  final drive_api.DriveItemSummary item;
  final String subtitle;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final isFolder = item.isFolder;
    final hasThumbnail = _shouldShowThumbnail(item);
    final thumbnailUrl = item.thumbnailUrl;
    final iconData = isFolder
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;
    final iconBackground = isFolder
        ? colors.secondary.withValues(alpha: 0.7)
        : colors.secondary.withValues(alpha: 0.45);
    final iconColor = isFolder
        ? colors.foreground
        : colors.foreground.withValues(alpha: 0.9);

    final content = FTile(
      onPress: onTap,
      style: (style) => style.copyWith(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: FWidgetStateMap({
          WidgetState.disabled: BoxDecoration(
            color: colors.disable(colors.background),
            borderRadius: BorderRadius.circular(16),
          ),
          WidgetState.hovered | WidgetState.pressed: BoxDecoration(
            color: colors.secondary.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          WidgetState.any: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(16),
          ),
        }),
        contentStyle: (contentStyle) => contentStyle.copyWith(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          titleTextStyle: FWidgetStateMap.all(
            typography.base.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
          subtitleTextStyle: FWidgetStateMap.all(
            typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ),
      ),
      prefix: SizedBox(
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
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      suffix: trailing,
    );

    if (onSecondaryTapDown == null) {
      return content;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons & kSecondaryMouseButton == 0) return;
        final box = context.findRenderObject();
        if (box is! RenderBox) return;
        final localPosition = box.globalToLocal(event.position);
        onSecondaryTapDown?.call(
          TapDownDetails(
            globalPosition: event.position,
            localPosition: localPosition,
            kind: event.kind,
          ),
        );
      },
      child: content,
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
