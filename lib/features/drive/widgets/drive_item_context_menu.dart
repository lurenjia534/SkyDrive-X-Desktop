import 'dart:async';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

enum DriveContextAction {
  createFolder('新建文件夹', FIcons.folderPlus),
  uploadFiles('上传文件', Icons.cloud_upload_rounded),
  download('下载', Icons.download_rounded),
  delete('删除', Icons.delete_outline_rounded),
  share('分享', Icons.share_outlined),
  move('移动', Icons.drive_file_move_outline),
  properties('属性', Icons.info_outline_rounded);

  const DriveContextAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

_DriveContextMenuOverlayState? _activeMenu;

Future<void> closeDriveItemContextMenu() async {
  if (_activeMenu != null) {
    await _activeMenu!._close();
  }
}

/// 在指针位置展示右键菜单，返回用户选择的动作。
Future<DriveContextAction?> showDriveItemContextMenu({
  required BuildContext context,
  required drive_api.DriveItemSummary item,
  required Offset globalPosition,
}) async {
  if (_activeMenu != null) {
    unawaited(_activeMenu!._close());
  }
  final actions = <DriveContextAction>[
    DriveContextAction.createFolder,
    if (item.isFolder) DriveContextAction.uploadFiles,
    if (!item.isFolder) DriveContextAction.download,
    DriveContextAction.delete,
    DriveContextAction.share,
    DriveContextAction.move,
    DriveContextAction.properties,
  ];

  final overlay = Overlay.of(context, rootOverlay: true);
  if (overlay == null) return null;
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox) return null;
  final position = overlayBox.globalToLocal(globalPosition);
  final completer = Completer<DriveContextAction?>();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _DriveContextMenuOverlay(
      position: position,
      actions: actions,
      onClose: (action) {
        if (entry.mounted) {
          entry.remove();
        }
        if (!completer.isCompleted) {
          completer.complete(action);
        }
      },
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

class _DriveContextMenuOverlay extends StatefulWidget {
  const _DriveContextMenuOverlay({
    required this.position,
    required this.actions,
    required this.onClose,
  });

  final Offset position;
  final List<DriveContextAction> actions;
  final ValueChanged<DriveContextAction?> onClose;

  @override
  State<_DriveContextMenuOverlay> createState() =>
      _DriveContextMenuOverlayState();
}

class _DriveContextMenuOverlayState extends State<_DriveContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _activeMenu = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.show();
    });
  }

  Future<void> _close([DriveContextAction? action]) async {
    if (_closing) return;
    _closing = true;
    if (_controller.status != AnimationStatus.dismissed &&
        _controller.status != AnimationStatus.reverse) {
      await _controller.hide();
    }
    if (!mounted) return;
    widget.onClose(action);
  }

  @override
  void dispose() {
    if (identical(_activeMenu, this)) {
      _activeMenu = null;
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: FPopoverMenu(
            popoverController: _controller,
            menuAnchor: Alignment.topLeft,
            childAnchor: Alignment.topLeft,
            spacing: FPortalSpacing.zero,
            onTapHide: _close,
            menu: [
              FItemGroup(
                divider: FItemDivider.full,
                children: widget.actions
                    .map(
                      (action) => FItem(
                        onPress: () => _close(action),
                        prefix: Icon(action.icon, size: 18),
                        title: Text(action.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
      ],
    );
  }
}
