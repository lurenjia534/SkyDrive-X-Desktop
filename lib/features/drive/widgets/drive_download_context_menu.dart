import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

enum DriveDownloadContextAction {
  revealInFolder('在文件夹中显示', Icons.folder_open_rounded);

  const DriveDownloadContextAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

_DriveDownloadContextMenuOverlayState? _activeMenu;

Future<void> closeDriveDownloadContextMenu() async {
  if (_activeMenu != null) {
    await _activeMenu!._close();
  }
}

Future<DriveDownloadContextAction?> showDriveDownloadContextMenu({
  required BuildContext context,
  required Offset globalPosition,
}) async {
  if (_activeMenu != null) {
    unawaited(_activeMenu!._close());
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  if (overlay == null) return null;
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox) return null;
  final position = overlayBox.globalToLocal(globalPosition);
  final completer = Completer<DriveDownloadContextAction?>();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _DriveDownloadContextMenuOverlay(
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

class _DriveDownloadContextMenuOverlay extends StatefulWidget {
  const _DriveDownloadContextMenuOverlay({
    required this.position,
    required this.onClose,
  });

  final Offset position;
  final ValueChanged<DriveDownloadContextAction?> onClose;

  @override
  State<_DriveDownloadContextMenuOverlay> createState() =>
      _DriveDownloadContextMenuOverlayState();
}

class _DriveDownloadContextMenuOverlayState
    extends State<_DriveDownloadContextMenuOverlay>
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

  Future<void> _close([DriveDownloadContextAction? action]) async {
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
                    onPress: () => _close(
                      DriveDownloadContextAction.revealInFolder,
                    ),
                    prefix: Icon(
                      DriveDownloadContextAction.revealInFolder.icon,
                      size: 18,
                    ),
                    title: Text(
                      DriveDownloadContextAction.revealInFolder.label,
                    ),
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
