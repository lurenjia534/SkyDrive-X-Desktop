import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/widgets/drive_file_action_sheet.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/delete.dart';

/// 封装文件/文件夹相关的常用操作，降低页面耦合。
class DriveItemActionService {
  static Future<void> showPropertiesSheet({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierLabel: '文件属性',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final widthFactor = screenWidth >= 1280
            ? 0.3
            : screenWidth >= 960
                ? 0.38
                : 0.6;
        return Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: Builder(
              builder: (sheetContext) => DriveFileActionSheet(
                item: item,
                onDownload: () async {
                  final started =
                      await DriveItemActionService.handleDownload(
                    context: context,
                    ref: ref,
                    item: item,
                  );
                  if (started && sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
                onClose: () => Navigator.of(sheetContext).maybePop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder:
          (dialogContext, animation, secondaryAnimation, child) {
        final slideTween = Tween<Offset>(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(
          position: animation.drive(slideTween),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutQuad,
            ),
            child: child,
          ),
        );
      },
    );
  }

  static Future<bool> handleDownload({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final manager = ref.read(driveDownloadManagerProvider.notifier);
    final queue = ref.read(driveDownloadManagerProvider);
    if (queue.isActive(item.id)) {
      messenger.showSnackBar(SnackBar(content: Text('下载中：${item.name}')));
      return false;
    }
    String targetDir;
    try {
      targetDir = await ref.read(downloadDirectoryProvider.future);
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text('无法获取下载目录：$err')),
      );
      return false;
    }
    try {
      await manager.enqueue(item, targetDirectory: targetDir);
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text('加入下载队列失败：$err')),
      );
      return false;
    }
    messenger.showSnackBar(SnackBar(content: Text('已加入下载队列：${item.name}')));
    return true;
  }

  static Future<void> confirmAndDelete({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除确认'),
          content: Text('确定将 "${item.name}" 移动到回收站吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await deleteDriveItem(itemId: item.id, ifMatch: null, bypassLocks: false);
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$err')));
      return;
    }

    final controller = ref.read(driveHomeControllerProvider.notifier);
    try {
      await controller.refresh(showSkeleton: false);
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text('删除成功，但刷新失败：$err')),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('已删除：${item.name}')));
  }
}
