import 'package:flutter/material.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

enum DriveContextAction {
  download('下载', Icons.download_rounded),
  delete('删除', Icons.delete_outline_rounded),
  share('分享', Icons.share_outlined),
  properties('属性', Icons.info_outline_rounded);

  const DriveContextAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 在指针位置展示右键菜单，返回用户选择的动作。
Future<DriveContextAction?> showDriveItemContextMenu({
  required BuildContext context,
  required drive_api.DriveItemSummary item,
  required Offset globalPosition,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox) return null;
  final overlaySize = overlayBox.size;

  final actions = <DriveContextAction>[
    if (!item.isFolder) DriveContextAction.download,
    DriveContextAction.delete,
    DriveContextAction.share,
    DriveContextAction.properties,
  ];

  return showMenu<DriveContextAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlaySize.width - globalPosition.dx,
      overlaySize.height - globalPosition.dy,
    ),
    items: actions
        .map(
          (action) => PopupMenuItem<DriveContextAction>(
            value: action,
            child: Row(
              children: [
                Icon(action.icon, size: 18),
                const SizedBox(width: 12),
                Text(action.label),
              ],
            ),
          ),
        )
        .toList(),
  );
}
