import 'dart:math' as math;

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
import 'package:skydrivex/src/rust/api/drive/rename.dart';
import 'package:skydrivex/utils/toast.dart';

/// 封装文件/文件夹相关的常用操作，降低页面耦合。
class DriveItemActionService {
  static const int _simpleUploadMaxBytes = 250 * 1024 * 1024;
  static const int _batchDeleteLimit = 20;

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
      barrierLabel: 'File properties',
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
    final controller = TextEditingController(text: 'New folder');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final result = await showFDialog<String>(
      context: context,
      barrierLabel: 'New folder',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        return FDialog(
          animation: animation,
          title: Text(
            'New folder',
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
                'Create a new folder in the current directory.',
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
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              style: FButtonStyle.primary(),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!context.mounted) return;
    if (result == null) return;
    final name = result.trim();
    if (name.isEmpty) {
      _showToast(context, 'Name cannot be empty');
      return;
    }

    final homeController = ref.read(driveHomeControllerProvider.notifier);
    try {
      final created = await homeController.createFolder(name);
      if (!context.mounted) return;
      _showToast(context, 'Folder created: ${created.name}');
    } catch (err) {
      if (!context.mounted) return;
      _showToast(context, 'Create folder failed: $err');
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
      _showToast(context, 'Downloading: ${item.name}');
      return false;
    }
    String targetDir;
    try {
      targetDir = await ref.read(downloadDirectoryProvider.future);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Unable to fetch download folder: $err');
      }
      return false;
    }
    if (!context.mounted) return false;
    try {
      await manager.enqueue(item, targetDirectory: targetDir);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Failed to add to download queue: $err');
      }
      return false;
    }
    if (!context.mounted) return false;
    _showToast(context, 'Added to download queue: ${item.name}');
    return true;
  }

  static Future<Set<String>?> enqueueBatchDownload({
    required BuildContext context,
    required WidgetRef ref,
    required List<drive_api.DriveItemSummary> items,
  }) async {
    if (items.isEmpty) return <String>{};

    final folderItems = <drive_api.DriveItemSummary>[];
    final fileItems = <drive_api.DriveItemSummary>[];
    for (final item in items) {
      if (item.isFolder) {
        folderItems.add(item);
      } else {
        fileItems.add(item);
      }
    }

    if (fileItems.isEmpty) {
      if (context.mounted) {
        _showToast(context, 'Selected items are folders. Choose files to download.');
      }
      return folderItems.map((item) => item.id).toSet();
    }

    String targetDir;
    try {
      targetDir = await ref.read(downloadDirectoryProvider.future);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Unable to fetch download folder: $err');
      }
      return items.map((item) => item.id).toSet();
    }
    if (!context.mounted) return null;

    final manager = ref.read(driveDownloadManagerProvider.notifier);
    drive_api.BatchDownloadResult result;
    try {
      result = await manager.enqueueBatch(
        fileItems,
        targetDirectory: targetDir,
      );
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Failed to add downloads: $err');
      }
      return items.map((item) => item.id).toSet();
    }

    if (!context.mounted) return null;

    final skippedIds = result.skipped.toSet();
    final failedIds = result.failed.toSet();
    final folderIds = folderItems.map((item) => item.id).toSet();
    final remainingIds = <String>{
      ...skippedIds,
      ...failedIds,
      ...folderIds,
    };

    final idToName = {
      for (final item in fileItems) item.id: item.name,
    };
    final queuedNames = fileItems
        .where(
          (item) =>
              !skippedIds.contains(item.id) && !failedIds.contains(item.id),
        )
        .map((item) => item.name)
        .toList();
    final skippedNames =
        skippedIds.map((id) => idToName[id] ?? id).toList();
    final failedNames = failedIds.map((id) => idToName[id] ?? id).toList();
    final folderNames = folderItems.map((item) => item.name).toList();

    if (queuedNames.isNotEmpty) {
      if (queuedNames.length == 1) {
        _showToast(context, 'Added to download queue: ${queuedNames.first}');
      } else {
        _showToast(context, 'Added to download queue: ${queuedNames.length} items');
      }
    }
    if (skippedNames.isNotEmpty) {
      _showToast(
        context,
        'Skipped ${skippedNames.length} already downloading: ${_formatNamePreview(skippedNames)}',
      );
    }
    if (folderNames.isNotEmpty) {
      _showToast(
        context,
        'Skipped ${folderNames.length} folders: ${_formatNamePreview(folderNames)}',
      );
    }
    if (failedNames.isNotEmpty) {
      _showToast(
        context,
        'Failed to add: ${_formatNamePreview(failedNames)}',
      );
    }

    if (queuedNames.isEmpty &&
        skippedNames.isEmpty &&
        failedNames.isEmpty &&
        folderNames.isEmpty) {
      _showToast(context, 'No files added to the download queue.');
    }

    return remainingIds;
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
          title: const Text('Confirm delete'),
          content: Text('Move "${item.name}" to the recycle bin?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await deleteDriveItem(itemId: item.id, ifMatch: null, bypassLocks: false);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Delete failed: $err');
      }
      return;
    }

    final controller = ref.read(driveHomeControllerProvider.notifier);
    try {
      await controller.refresh(showSkeleton: false);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Deleted, but refresh failed: $err');
      }
      return;
    }
    if (context.mounted) {
      _showToast(context, 'Deleted: ${item.name}');
    }
  }

  static Future<Set<String>?> confirmAndDeleteBatch({
    required BuildContext context,
    required WidgetRef ref,
    required List<drive_api.DriveItemSummary> items,
  }) async {
    if (items.isEmpty) return <String>{};

    final count = items.length;
    final preview = items.take(4).map((item) => item.name).toList();
    final confirmed = await showFDialog<bool>(
      context: context,
      barrierLabel: 'Confirm delete',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        final summary = count == 1
            ? 'Move "${items.first.name}" to the recycle bin?'
            : 'Move $count items to the recycle bin?';
        return FDialog(
          animation: animation,
          title: Text(
            'Confirm delete',
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
                summary,
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              if (count > 1) ...[
                const SizedBox(height: 12),
                ...preview.map(
                  (name) => Text(
                    '- $name',
                    style: typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                if (count > preview.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '...and ${count - preview.length} more',
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          direction: Axis.horizontal,
          actions: [
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(false),
              style: FButtonStyle.outline(),
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(true),
              style: FButtonStyle.destructive(),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return null;

    final failures = <String>{};
    final failedNames = <String>[];
    var completed = 0;
    var cancelled = false;

    if (count > _batchDeleteLimit) {
      var cancelRequested = false;
      var started = false;
      await showFDialog<void>(
        context: context,
        barrierLabel: 'Deleting items',
        barrierDismissible: false,
        builder: (dialogContext, style, animation) {
          final theme = dialogContext.theme;
          final colors = theme.colors;
          final typography = theme.typography;
          return StatefulBuilder(
            builder: (context, setState) {
              if (!started) {
                started = true;
                Future.microtask(() async {
                  final result = await _deleteItemsWithBatch(
                    items,
                    onProgress: (value) {
                      if (!dialogContext.mounted) return;
                      setState(() => completed = value);
                    },
                    isCancelled: () => cancelRequested,
                  );
                  failures
                    ..clear()
                    ..addAll(result.$1);
                  failedNames
                    ..clear()
                    ..addAll(result.$2);
                  completed = result.$3;
                  cancelled = result.$4;
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                });
              }

              final progress = count == 0 ? 0.0 : completed / count;
              return FDialog(
                animation: animation,
                title: Text(
                  'Deleting items',
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
                      'Deleting $completed/$count',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FDeterminateProgress(
                      value: progress.clamp(0, 1),
                      style: (style) => style.copyWith(
                        constraints: const BoxConstraints.tightFor(height: 8),
                        trackDecoration: BoxDecoration(
                          color: colors.secondary.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        fillDecoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    if (cancelRequested) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Cancelling... will stop after the current batch.',
                        style: typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
                direction: Axis.horizontal,
                actions: [
                  FButton(
                    onPress: cancelRequested
                        ? null
                        : () => setState(() => cancelRequested = true),
                    style: FButtonStyle.outline(),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );
    } else {
      final result = await _deleteItemsWithBatch(
        items,
        onProgress: (value) => completed = value,
        isCancelled: () => false,
      );
      failures
        ..clear()
        ..addAll(result.$1);
      failedNames
        ..clear()
        ..addAll(result.$2);
      completed = result.$3;
      cancelled = result.$4;
    }

    final controller = ref.read(driveHomeControllerProvider.notifier);
    try {
      if (completed > 0) {
        await controller.refresh(showSkeleton: false);
      }
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Deleted, but refresh failed: $err');
      }
    }

    if (!context.mounted) return failures;

    if (cancelled) {
      _showToast(context, 'Delete cancelled: $completed/$count processed');
      return failures;
    }

    if (failures.isEmpty) {
      _showToast(
        context,
        count == 1 ? 'Deleted: ${items.first.name}' : 'Deleted $count items',
      );
    } else {
      final failedPreview = _formatNamePreview(failedNames, max: 3);
      _showToast(
        context,
        'Deleted ${count - failures.length}/$count items. Failed: $failedPreview',
      );
    }

    return failures;
  }

  static Future<void> showShareDialog({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    await showFDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierLabel: 'Share link',
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
      barrierLabel: 'Close move panel',
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
                    _showToast(dialogContext, 'Move succeeded');
                    // 移动完成后刷新列表，但避免在对话框关闭前触发界面跳转。
                    await ref
                        .read(driveHomeControllerProvider.notifier)
                        .refresh(showSkeleton: true);
                  }
                } catch (err) {
                  if (dialogContext.mounted) {
                    _showToast(dialogContext, 'Move failed: $err');
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

  static Future<void> promptRename({
    required BuildContext context,
    required WidgetRef ref,
    required drive_api.DriveItemSummary item,
  }) async {
    final controller = TextEditingController(text: item.name);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final result = await showFDialog<String>(
      context: context,
      barrierLabel: 'Rename',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        return FDialog(
          animation: animation,
          title: Text(
            'Rename',
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
                'Enter a new name for this item.',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(controller: controller),
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
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              style: FButtonStyle.primary(),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!context.mounted) return;
    if (result == null) return;
    final name = result.trim();
    if (name.isEmpty) {
      _showToast(context, 'Name cannot be empty');
      return;
    }
    if (name == item.name) {
      return;
    }

    try {
      await renameDriveItem(
        itemId: item.id,
        newName: name,
        ifMatch: null,
      );
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Rename failed: $err');
      }
      return;
    }

    final controllerRef = ref.read(driveHomeControllerProvider.notifier);
    try {
      await controllerRef.refresh(showSkeleton: false);
    } catch (err) {
      if (context.mounted) {
        _showToast(context, 'Renamed, but refresh failed: $err');
      }
      return;
    }
    if (context.mounted) {
      _showToast(context, 'Renamed to: $name');
    }
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
      _showToast(context, 'Added to upload queue: $uploadedCount files');
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    }
    if (!context.mounted) return;
    if (failures.isNotEmpty) {
      _showToast(context, 'Some files failed to upload: ${failures.join('、')}');
    }
  }

  static void _showToast(BuildContext context, String message) {
    showToast(context, message);
  }

  static Future<(Set<String>, List<String>, int, bool)> _deleteItemsWithBatch(
    List<drive_api.DriveItemSummary> items, {
    required ValueChanged<int> onProgress,
    required bool Function() isCancelled,
  }) async {
    if (items.isEmpty) return (<String>{}, <String>[], 0, false);
    final failures = <String>{};
    final failedNames = <String>[];
    var completed = 0;
    var cancelled = false;
    for (var start = 0; start < items.length; start += _batchDeleteLimit) {
      if (isCancelled()) {
        cancelled = true;
        for (final item in items.sublist(start)) {
          failures.add(item.id);
          failedNames.add(item.name);
        }
        break;
      }
      final end = math.min(start + _batchDeleteLimit, items.length);
      final chunk = items.sublist(start, end);
      final idToName = {
        for (final item in chunk) item.id: item.name,
      };
      try {
        final failedIds = await deleteDriveItemsBatch(
          itemIds: chunk.map((item) => item.id).toList(),
          bypassLocks: false,
        );
        for (final id in failedIds) {
          failures.add(id);
          failedNames.add(idToName[id] ?? id);
        }
      } catch (_) {
        for (final item in chunk) {
          failures.add(item.id);
          failedNames.add(item.name);
        }
      }
      completed += chunk.length;
      onProgress(completed);
    }
    return (failures, failedNames, completed, cancelled);
  }

  static String _formatNamePreview(List<String> names, {int max = 3}) {
    if (names.isEmpty) return 'Unknown';
    final head = names.take(max).toList();
    final remaining = names.length - head.length;
    if (remaining > 0) {
      return '${head.join(', ')} and $remaining more';
    }
    return head.join(', ');
  }
}
