import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_context_menu.dart';

enum DriveBackgroundAction {
  createFolder('新建文件夹', FIcons.folderPlus),
  uploadFiles('上传文件', Icons.cloud_upload_rounded);

  const DriveBackgroundAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

_DriveBackgroundContextMenuOverlayState? _activeMenu;

Future<void> closeDriveBackgroundContextMenu() async {
  if (_activeMenu != null) {
    await _activeMenu!._close();
  }
}

Future<DriveBackgroundAction?> showDriveBackgroundContextMenu({
  required BuildContext context,
  required Offset globalPosition,
}) async {
  unawaited(closeDriveItemContextMenu());
  if (_activeMenu != null) {
    unawaited(_activeMenu!._close());
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  if (overlay == null) return null;
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox) return null;
  final position = overlayBox.globalToLocal(globalPosition);
  final completer = Completer<DriveBackgroundAction?>();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _DriveBackgroundContextMenuOverlay(
      position: position,
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

class _DriveBackgroundContextMenuOverlay extends StatefulWidget {
  const _DriveBackgroundContextMenuOverlay({
    required this.position,
    required this.onClose,
  });

  final Offset position;
  final ValueChanged<DriveBackgroundAction?> onClose;

  @override
  State<_DriveBackgroundContextMenuOverlay> createState() =>
      _DriveBackgroundContextMenuOverlayState();
}

class _DriveBackgroundContextMenuOverlayState
    extends State<_DriveBackgroundContextMenuOverlay>
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

  Future<void> _close([DriveBackgroundAction? action]) async {
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
            control: FPopoverControl.managed(
              controller: _controller,
            ),
            menuAnchor: Alignment.topLeft,
            childAnchor: Alignment.topLeft,
            spacing: FPortalSpacing.zero,
            onTapHide: _close,
            menu: [
              FItemGroup(
                divider: FItemDivider.full,
                children: [
                  FItem(
                    onPress: () =>
                        _close(DriveBackgroundAction.createFolder),
                    prefix: const Icon(FIcons.folderPlus, size: 18),
                    title: const Text('新建文件夹'),
                  ),
                  FItem(
                    onPress: () => _close(DriveBackgroundAction.uploadFiles),
                    prefix:
                        const Icon(Icons.cloud_upload_rounded, size: 18),
                    title: const Text('上传文件'),
                  ),
                ],
              ),
            ],
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
      ],
    );
  }
}
