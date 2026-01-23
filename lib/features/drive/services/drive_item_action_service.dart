import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';
import 'package:skydrivex/features/drive/widgets/drive_move_sheet.dart';
import 'package:skydrivex/features/drive/providers/drive_share_provider.dart';
import 'package:skydrivex/features/drive/widgets/drive_file_action_sheet.dart';
import 'package:skydrivex/features/drive/widgets/drive_share_dialog.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/delete.dart';
import 'package:skydrivex/src/rust/api/drive/move_item.dart';
import 'package:skydrivex/utils/toast.dart';

/// 封装文件/文件夹相关的常用操作，降低页面耦合。
class DriveItemActionService {
  static const int _simpleUploadMaxBytes = 250 * 1024 * 1024;

  static Future<void> showPropertiesSheet({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final widthFactor = screenWidth >= 1280
        ? 0.3
        : screenWidth >= 960
        ? 0.38
        : 0.6;
    await showFSheet(
      context: context,
      side: FLayout.rtl,
      useRootNavigator: true,
      barrierLabel: '文件属性',
      barrierDismissible: true,
      draggable: false,
      mainAxisMaxRatio: widthFactor,
      builder: (sheetContext) => DriveFileActionSheet(
        item: item,
        onDownload: () async {
          final started = await DriveItemActionService.handleDownload(
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
    );
  }

  static Future<void> promptCreateFolder({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final controller = TextEditingController(text: '新建文件夹');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final result = await showFDialog<String>(
      context: context,
      barrierLabel: '新建文件夹',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        return FDialog(
          animation: animation,
          title: Text(
            '新建文件夹',
            style: typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '在当前目录创建一个新文件夹。',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: controller,
                ),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmit: (_) =>
                    Navigator.of(dialogContext).pop(controller.text),
              ),
            ],
          ),
          direction: Axis.horizontal,
          actions: [
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(),
              style: FButtonStyle.outline(),
              child: const Text('取消'),
            ),
            FButton(
              onPress: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              style: FButtonStyle.primary(),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) return;
    final name = result.trim();
    if (name.isEmpty) {
      _showToast(context, '名称不能为空');
      return;
    }

    final homeController = ref.read(driveHomeControllerProvider.notifier);
    try {
      final created = await homeController.createFolder(name);
      if (!context.mounted) return;
      _showToast(context, '已创建文件夹：${created.name}');
    } catch (err) {
      if (!context.mounted) return;
      _showToast(context, '新建文件夹失败：$err');
    }
  }

  static Future<bool> handleDownload({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    final manager = ref.read(driveDownloadManagerProvider.notifier);
    final queue = ref.read(driveDownloadManagerProvider);
    if (queue.isActive(item.id)) {
      _showToast(context, '下载中：${item.name}');
      return false;
    }
    String targetDir;
    try {
      targetDir = await ref.read(downloadDirectoryProvider.future);
    } catch (err) {
      _showToast(context, '无法获取下载目录：$err');
      return false;
    }
    try {
      await manager.enqueue(item, targetDirectory: targetDir);
    } catch (err) {
      _showToast(context, '加入下载队列失败：$err');
      return false;
    }
    _showToast(context, '已加入下载队列：${item.name}');
    return true;
  }

  static Future<void> confirmAndDelete({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
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
      _showToast(context, '删除失败：$err');
      return;
    }

    final controller = ref.read(driveHomeControllerProvider.notifier);
    try {
      await controller.refresh(showSkeleton: false);
    } catch (err) {
      _showToast(context, '删除成功，但刷新失败：$err');
      return;
    }
    _showToast(context, '已删除：${item.name}');
  }

  static Future<void> showShareDialog({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    await showFDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierLabel: '分享链接',
      builder: (dialogContext, style, animation) {
        return ProviderScope(
          overrides: [shareTargetItemProvider.overrideWithValue(item)],
          child: DriveShareDialog(animation: animation),
        );
      },
    );
  }

  static Future<void> showMoveSheet({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: '关闭移动侧栏',
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.34,
            child: DriveMoveSheet(
              item: item,
              onMove: (targetFolderId) async {
                try {
                  await moveDriveItem(
                    itemId: item.id,
                    newParentId: targetFolderId,
                    newName: null,
                    ifMatch: null,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    _showToast(dialogContext, '移动成功');
                    // 移动完成后刷新列表，但避免在对话框关闭前触发界面跳转。
                    await ref
                        .read(driveHomeControllerProvider.notifier)
                        .refresh(showSkeleton: true);
                  }
                } catch (err) {
                  if (dialogContext.mounted) {
                    _showToast(dialogContext, '移动失败：$err');
                  }
                }
              },
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
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

  static Future<void> promptUploadFiles({
    required BuildContext context,
    required WidgetRef ref,
    String? parentId,
  }) async {
    final files = await openFiles();
    if (files.isEmpty) return;

    final breadcrumbs =
        ref.read(driveHomeControllerProvider).asData?.value.breadcrumbs ?? [];
    final targetParentId = parentId ?? (breadcrumbs.isNotEmpty
        ? breadcrumbs.last.id
        : null);
    final manager = ref.read(driveUploadManagerProvider.notifier);
    var uploadedCount = 0;
    final failures = <String>[];

    for (final file in files) {
      try {
        final size = await file.length();
        if (size <= _simpleUploadMaxBytes) {
          final bytes = await file.readAsBytes();
          await manager.enqueue(
            parentId: targetParentId,
            fileName: file.name,
            localPath: file.path,
            content: bytes,
            overwrite: false,
          );
        } else {
          await manager.enqueueLarge(
            parentId: targetParentId,
            fileName: file.name,
            localPath: file.path,
            overwrite: false,
          );
        }
        uploadedCount += 1;
      } catch (err) {
        failures.add('${file.name}：$err');
      }
    }

    if (!context.mounted) return;

    if (uploadedCount > 0) {
      _showToast(context, '已加入上传队列：$uploadedCount 个文件');
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    }
    if (failures.isNotEmpty) {
      _showToast(context, '部分文件上传失败：${failures.join('、')}');
    }
  }

  static void _showToast(BuildContext context, String message) {
    showToast(context, message);
  }
}
