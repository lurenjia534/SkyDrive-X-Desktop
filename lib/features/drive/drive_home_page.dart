import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/services/drive_item_action_service.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/features/drive/widgets/drive_breadcrumb_bar.dart';
import 'package:skydrivex/features/drive/widgets/drive_download_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_empty_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_error_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_context_menu.dart';
import 'package:skydrivex/features/drive/widgets/drive_inline_progress_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_load_more_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_loading_list.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveHomePage extends ConsumerWidget {
  const DriveHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(driveHomeControllerProvider);

    return asyncState.when(
      data: (data) => _DriveHomeView(state: data, isRefreshing: false),
      loading: () {
        final previous = asyncState.asData?.value;
        if (previous != null) {
          return _DriveHomeView(state: previous, isRefreshing: true);
        }
        return const DriveLoadingList(key: ValueKey('drive-loading'));
      },
      error: (error, _) {
        final previous = asyncState.asData?.value;
        if (previous != null) {
          return _DriveHomeView(state: previous, isRefreshing: false);
        }
        return DriveErrorView(
          message: error.toString(),
          onRetry: () => ref
              .read(driveHomeControllerProvider.notifier)
              .refresh(showSkeleton: true),
        );
      },
    );
  }
}

class _DriveHomeView extends ConsumerWidget {
  const _DriveHomeView({required this.state, required this.isRefreshing});

  final DriveHomeState state;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(driveHomeControllerProvider.notifier);
    final downloadQueue = ref.watch(driveDownloadManagerProvider);
    final showInlineLoadingBar =
        (isRefreshing || state.isRefreshing) && state.items.isNotEmpty;
    final showEmptyState = state.items.isEmpty;
    final listItemCount =
        state.items.length +
        (state.nextLink != null ? 1 : 0) +
        (showEmptyState ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: DriveBreadcrumbBar(
            segments: state.breadcrumbs,
            onRootTap: () => controller.tapBreadcrumb(null),
            onSegmentTap: controller.tapBreadcrumb,
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              RefreshIndicator(
                key: const ValueKey('drive-content'),
                onRefresh: () => controller.refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: listItemCount,
                  itemBuilder: (context, index) {
                    if (showEmptyState && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: DriveEmptyView(),
                      );
                    }
                    if (index >= state.items.length) {
                      return DriveLoadMoreTile(
                        isLoading: state.isLoadingMore,
                        onLoadMore: () async {
                          try {
                            await controller.loadMore();
                          } catch (err) {
                            if (!context.mounted) return;
                            _showSnack(context, '加载更多失败：$err');
                          }
                        },
                      );
                    }
                    final item = state.items[index];
                    final subtitle = buildDriveSubtitle(item);
                    drive_api.DownloadTask? activeTask;
                    for (final task in downloadQueue.active) {
                      if (task.item.id == item.id) {
                        activeTask = task;
                        break;
                      }
                    }
                    final trailing = item.isFolder
                        ? null
                        : DriveDownloadIndicator(
                            isDownloading: activeTask != null,
                            progress: activeTask?.progressRatio,
                            colorScheme: Theme.of(context).colorScheme,
                          );
                    return DriveItemTile(
                      item: item,
                      subtitle: subtitle,
                      colorScheme: Theme.of(context).colorScheme,
                      onTap: () => _handleItemTap(context, ref, item),
                      onSecondaryTapDown: (details) =>
                          _handleContextMenu(context, ref, item, details),
                      trailing: trailing,
                    );
                  },
                ),
              ),
              if (showInlineLoadingBar)
                const Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: DriveInlineProgressIndicator(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _handleItemTap(
  BuildContext context,
  WidgetRef ref,
  drive_api.DriveItemSummary item,
) async {
  final controller = ref.read(driveHomeControllerProvider.notifier);
  if (item.isFolder) {
    await controller.openFolder(item);
    return;
  }
  await DriveItemActionService.showPropertiesSheet(
    context: context,
    ref: ref,
    item: item,
  );
}

Future<void> _handleContextMenu(
  BuildContext context,
  WidgetRef ref,
  drive_api.DriveItemSummary item,
  TapDownDetails details,
) async {
  final selected = await showDriveItemContextMenu(
    context: context,
    item: item,
    globalPosition: details.globalPosition,
  );

  if (selected == null) return;
  if (!context.mounted) return;
  switch (selected) {
    case DriveContextAction.download:
      await DriveItemActionService.handleDownload(
        context: context,
        ref: ref,
        item: item,
      );
      break;
    case DriveContextAction.delete:
      await DriveItemActionService.confirmAndDelete(
        context: context,
        ref: ref,
        item: item,
      );
      break;
    case DriveContextAction.properties:
      await DriveItemActionService.showPropertiesSheet(
        context: context,
        ref: ref,
        item: item,
      );
      break;
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
